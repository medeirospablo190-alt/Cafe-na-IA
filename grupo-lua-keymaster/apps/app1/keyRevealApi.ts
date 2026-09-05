import { App1ApiError, type App1MenuKey } from "./api";
import { requireApiUrl } from "./config";

export type RevealableMenuKey = App1MenuKey & {
  can_reveal?: boolean;
};

export async function revealApp1MenuKey(
  sessionToken: string,
  deviceToken: string,
  keyId: string
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45_000);
  try {
    const response = await fetch(
      `${requireApiUrl()}/v1/app1/menu-admin/keys/${encodeURIComponent(keyId)}/reveal`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${sessionToken}`,
          "x-app1-device-token": deviceToken,
          "cache-control": "no-store"
        },
        signal: controller.signal
      }
    );
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new App1ApiError(
        String(data?.message || `HTTP ${response.status}`),
        response.status,
        String(data?.code || "HTTP_ERROR")
      );
    }
    return data as {
      ok: true;
      key: {
        id: string;
        kind: "FREE" | "VIP";
        key_hint: string;
        value: string;
      };
    };
  } catch (error) {
    if (error instanceof App1ApiError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new App1ApiError(
        "O servidor demorou demais para recuperar a chave. Tente novamente.",
        0,
        "NETWORK_TIMEOUT"
      );
    }
    throw new App1ApiError(
      error instanceof Error ? error.message : "Não foi possível recuperar a chave.",
      0,
      "NETWORK_ERROR"
    );
  } finally {
    clearTimeout(timeout);
  }
}
