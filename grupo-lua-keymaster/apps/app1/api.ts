import { requireApiUrl } from "./config";
import type { App1DeviceIdentity } from "./device";

export type App1Role = "ADM" | "DEV";
export type SessionKind = "PROVISIONAL" | "FULL";
export type LibraryKind = "CODE" | "LOADSTRING";
export type MenuKeyKind = "FREE" | "VIP";
export type MenuKeyDurationUnit = "HOURS" | "DAYS" | "MONTHS" | "PERMANENT";
export type MenuKeyAccessState = "READY" | "ACTIVE" | "WAITING_ADMIN" | "EXPIRED";

export type OnboardingState = {
  completed: boolean;
  termsAccepted: boolean;
  publicNameVerified: boolean;
};

export type PublicAccount = {
  profileId: string | null;
  publicName: string | null;
  role: App1Role;
  status: string;
  onboarding: OnboardingState;
};

export type App1Session = {
  kind: SessionKind;
  expiresAt: string;
};

export type App1ManagedMenu = {
  id: string;
  public_id: string;
  name: string;
  source_url: string;
  status: "ACTIVE" | "SUSPENDED";
  key_count: number;
  created_at: string;
  updated_at: string;
};

export type App1MenuKey = {
  id: string;
  menu_id: string;
  kind: MenuKeyKind;
  status: "ACTIVE" | "SUSPENDED" | "REVOKED";
  key_hint: string;
  note: string | null;
  access_state: MenuKeyAccessState;
  duration_value: number | null;
  duration_unit: MenuKeyDurationUnit | null;
  access_started_at: string | null;
  access_until: string | null;
  bound_device: boolean;
  bound_device_hint: string | null;
  use_count: number;
  last_used_at: string | null;
  created_at: string;
  updated_at: string;
  revoked_at: string | null;
  usable: boolean;
};

export type LibraryItemSummary = {
  id: string;
  kind: LibraryKind;
  title: string;
  favorite: boolean;
  preview: string;
  contentBytes: number;
  createdAt: string;
  updatedAt: string;
  sharedCount: number;
};

export type LibraryItem = LibraryItemSummary & {
  content: string;
};

export type LibraryPage = {
  ok: true;
  items: LibraryItemSummary[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
  nextOffset: number | null;
};

export type FeedPost = {
  id: string;
  kind: LibraryKind;
  createdAt: string;
  expiresAt: string;
  author: {
    profileId: string | null;
    publicName: string;
  };
  item: {
    id: string;
    title: string;
    content: string;
    contentBytes: number;
    truncated: boolean;
  };
};

export class App1ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code: string
  ) {
    super(message);
  }
}

const API_TIMEOUT_MS = 45_000;

async function apiFetch(url: string, init: RequestInit = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new App1ApiError(
        "O servidor demorou demais para responder. Verifique sua conexão e tente novamente.",
        0,
        "NETWORK_TIMEOUT"
      );
    }
    if (error instanceof App1ApiError) throw error;
    throw new App1ApiError(
      error instanceof Error ? error.message : "Não foi possível conectar ao servidor.",
      0,
      "NETWORK_ERROR"
    );
  } finally {
    clearTimeout(timeout);
  }
}

async function parseResponse<T>(response: Response): Promise<T> {
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new App1ApiError(
      String(data?.message || `HTTP ${response.status}`),
      response.status,
      String(data?.code || "HTTP_ERROR")
    );
  }
  return data as T;
}

function authHeaders(sessionToken: string, deviceToken: string) {
  return {
    authorization: `Bearer ${sessionToken}`,
    "x-app1-device-token": deviceToken
  };
}

export async function loginApp1(
  login: string,
  credential: string,
  identity: App1DeviceIdentity,
  savedDeviceToken: string
) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/login`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      login,
      credential,
      deviceLabel: "GRUPO_LUA_APP1_V0_1",
      ...identity,
      deviceToken: savedDeviceToken
    })
  });

  return parseResponse<{
    ok: true;
    token: string;
    expiresAt: string;
    sessionKind: SessionKind;
    deviceToken?: string;
    account: PublicAccount;
    serverTime: string;
    integrityVerified: boolean;
  }>(response);
}

export async function getMe(sessionToken: string, deviceToken: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/me`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{
    ok: true;
    session: App1Session;
    account: PublicAccount;
  }>(response);
}

export async function acceptTerms(sessionToken: string, deviceToken: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/onboarding/accept-terms`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...authHeaders(sessionToken, deviceToken)
    },
    body: JSON.stringify({ accepted: true })
  });
  return parseResponse<{
    ok: true;
    termsVersion: string;
    privacyVersion: string;
  }>(response);
}

export async function confirmPublicName(
  sessionToken: string,
  deviceToken: string,
  publicName: string
) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/onboarding/public-name`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...authHeaders(sessionToken, deviceToken)
    },
    body: JSON.stringify({ publicName })
  });
  return parseResponse<{
    ok: true;
    account: PublicAccount;
    session: App1Session;
  }>(response);
}

export async function listLibraryItems(
  sessionToken: string,
  deviceToken: string,
  options: {
    kind?: LibraryKind;
    q?: string;
    favorite?: boolean;
    limit?: number;
    offset?: number;
  } = {}
) {
  const params = new URLSearchParams();
  if (options.kind) params.set("kind", options.kind);
  if (options.q) params.set("q", options.q);
  if (options.favorite !== undefined) params.set("favorite", String(options.favorite));
  if (options.limit !== undefined) params.set("limit", String(options.limit));
  if (options.offset !== undefined) params.set("offset", String(options.offset));
  const suffix = params.toString() ? `?${params.toString()}` : "";
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library${suffix}`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<LibraryPage>(response);
}

export async function getLibraryItem(sessionToken: string, deviceToken: string, id: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library/${encodeURIComponent(id)}`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{ ok: true; item: LibraryItem }>(response);
}

export async function createLibraryItem(
  sessionToken: string,
  deviceToken: string,
  input: { kind: LibraryKind; title: string; content: string }
) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library`, {
    method: "POST",
    headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
    body: JSON.stringify(input)
  });
  return parseResponse<{ ok: true; item: LibraryItem }>(response);
}

export async function updateLibraryItem(
  sessionToken: string,
  deviceToken: string,
  id: string,
  input: { title?: string; content?: string }
) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library/${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
    body: JSON.stringify(input)
  });
  return parseResponse<{ ok: true; item: LibraryItem }>(response);
}

export async function setLibraryFavorite(
  sessionToken: string,
  deviceToken: string,
  ids: string[],
  favorite: boolean
) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library/bulk/favorite`, {
    method: "POST",
    headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
    body: JSON.stringify({ ids, favorite })
  });
  return parseResponse<{ ok: true; updatedCount: number }>(response);
}

export async function deleteLibraryItems(sessionToken: string, deviceToken: string, ids: string[]) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library/bulk/delete`, {
    method: "POST",
    headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
    body: JSON.stringify({ ids })
  });
  return parseResponse<{ ok: true; deletedCount: number }>(response);
}

export async function shareLibraryItem(sessionToken: string, deviceToken: string, id: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/library/${encodeURIComponent(id)}/share`, {
    method: "POST",
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{ ok: true; post: { id: string; post_kind: LibraryKind; created_at: string; expires_at: string } }>(response);
}

export async function listFeedPosts(sessionToken: string, deviceToken: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/feed`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{ ok: true; posts: FeedPost[] }>(response);
}

export async function getFeedPost(sessionToken: string, deviceToken: string, id: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/feed/${encodeURIComponent(id)}`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{ ok: true; post: FeedPost }>(response);
}

export async function listApp1ManagedMenus(sessionToken: string, deviceToken: string) {
  const response = await apiFetch(`${requireApiUrl()}/v1/app1/menu-admin/menus`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{ ok: true; menus: App1ManagedMenu[] }>(response);
}

export async function listApp1MenuKeys(sessionToken: string, deviceToken: string, menuId: string) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/keys`,
    { headers: authHeaders(sessionToken, deviceToken) }
  );
  return parseResponse<{ ok: true; keys: App1MenuKey[] }>(response);
}

export async function createApp1MenuKey(
  sessionToken: string,
  deviceToken: string,
  menuId: string,
  input: {
    kind: MenuKeyKind;
    durationValue?: number;
    durationUnit?: Exclude<MenuKeyDurationUnit, "HOURS">;
    note?: string;
  }
) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/menus/${encodeURIComponent(menuId)}/keys`,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
      body: JSON.stringify(input)
    }
  );
  return parseResponse<{ ok: true; key: App1MenuKey & { value: string; revealOnce: true } }>(response);
}

export async function releaseApp1FreeKey(
  sessionToken: string,
  deviceToken: string,
  keyId: string,
  durationHours = 24
) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/release-free`,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
      body: JSON.stringify({ durationHours })
    }
  );
  return parseResponse<{ ok: true; key: App1MenuKey }>(response);
}

export async function configureApp1VipKey(
  sessionToken: string,
  deviceToken: string,
  keyId: string,
  durationUnit: "DAYS" | "MONTHS" | "PERMANENT",
  durationValue?: number
) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/configure-vip`,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
      body: JSON.stringify({ durationUnit, durationValue })
    }
  );
  return parseResponse<{ ok: true; key: App1MenuKey }>(response);
}

export async function resetApp1MenuKeyDevice(sessionToken: string, deviceToken: string, keyId: string) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/reset-device`,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
      body: "{}"
    }
  );
  return parseResponse<{ ok: true; key: App1MenuKey }>(response);
}

export async function setApp1MenuKeyState(
  sessionToken: string,
  deviceToken: string,
  keyId: string,
  action: "suspend" | "restore" | "revoke"
) {
  const response = await apiFetch(
    `${requireApiUrl()}/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/state/${action}`,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...authHeaders(sessionToken, deviceToken) },
      body: "{}"
    }
  );
  return parseResponse<{ ok: true; key: App1MenuKey }>(response);
}
