import { requireApiUrl } from "./config";
import type { App1DeviceIdentity } from "./device";

export type App1Role = "ADM" | "DEV";
export type SessionKind = "PROVISIONAL" | "FULL";

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

export class App1ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public code: string
  ) {
    super(message);
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
  const response = await fetch(`${requireApiUrl()}/v1/app1/login`, {
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
  const response = await fetch(`${requireApiUrl()}/v1/app1/me`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
  return parseResponse<{
    ok: true;
    session: App1Session;
    account: PublicAccount;
  }>(response);
}

export async function acceptTerms(sessionToken: string, deviceToken: string) {
  const response = await fetch(`${requireApiUrl()}/v1/app1/onboarding/accept-terms`, {
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
  const response = await fetch(`${requireApiUrl()}/v1/app1/onboarding/public-name`, {
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
