import { API_URL } from "./config";

const TIMEOUT_MS = 45_000;

export async function clearAuditHistory(session: string) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(`${API_URL}/v1/keymaster/audit`, {
      method: "DELETE",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${session}`
      }
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(String(data?.message || `HTTP ${response.status}`));
    }
    return data as {
      ok: true;
      auditDeleted: number;
      loginAttemptsDeleted: number;
    };
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new Error("O servidor demorou demais para responder. Tente novamente.");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}
