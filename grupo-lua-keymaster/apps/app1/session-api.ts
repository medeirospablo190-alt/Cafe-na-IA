import { requireApiUrl } from "./config";
import { App1ApiError } from "./api";

const API_TIMEOUT_MS = 45_000;

export async function logoutApp1(sessionToken: string, deviceToken: string) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const response = await fetch(`${requireApiUrl()}/v1/app1/logout`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        authorization: `Bearer ${sessionToken}`,
        "x-app1-device-token": deviceToken,
        "content-type": "application/json"
      },
      body: "{}"
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new App1ApiError(
        String(data?.message || `HTTP ${response.status}`),
        response.status,
        String(data?.code || "HTTP_ERROR")
      );
    }
    return data as { ok: true };
  } catch (error) {
    if (error instanceof App1ApiError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new App1ApiError(
        "O servidor demorou demais para confirmar o encerramento da sessão.",
        0,
        "NETWORK_TIMEOUT"
      );
    }
    throw new App1ApiError(
      error instanceof Error ? error.message : "Não foi possível encerrar a sessão no servidor.",
      0,
      "NETWORK_ERROR"
    );
  } finally {
    clearTimeout(timeout);
  }
}
