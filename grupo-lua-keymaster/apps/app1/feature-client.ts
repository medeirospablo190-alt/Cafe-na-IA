import { App1ApiError } from "./api";
import { requireApiUrl } from "./config";

const API_TIMEOUT_MS = 45_000;

export function app1AuthHeaders(sessionToken: string, deviceToken: string) {
  return {
    authorization: `Bearer ${sessionToken}`,
    "x-app1-device-token": deviceToken
  };
}

export async function app1FeatureRequest<T>(
  path: string,
  sessionToken: string,
  deviceToken: string,
  init: RequestInit = {}
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  const headers = {
    ...app1AuthHeaders(sessionToken, deviceToken),
    ...(init.headers || {})
  };

  let response: Response;
  try {
    response = await fetch(`${requireApiUrl()}${path}`, {
      ...init,
      headers,
      signal: controller.signal
    });
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
