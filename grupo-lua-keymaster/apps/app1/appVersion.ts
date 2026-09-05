import * as Application from "expo-application";
import Constants from "expo-constants";
import { Platform } from "react-native";
import { API_URL, requireApiUrl } from "./config";

export type AppCompatibilityStatus =
  | "COMPATIBLE"
  | "UPDATE_AVAILABLE"
  | "UPDATE_REQUIRED";

export type AppCompatibilityResult = {
  ok: true;
  app: "APP1";
  platform: string;
  currentVersion: string;
  minSupportedVersion: string;
  latestVersion: string;
  status: AppCompatibilityStatus;
  updateRequired: boolean;
  updateAvailable: boolean;
  message: string;
  serverTime: string;
};

type VersionedFetchInput = Parameters<typeof fetch>[0] | URL;

export const APP1_VERSION = String(
  Constants.expoConfig?.version || Application.nativeApplicationVersion || "0.0.0"
).trim();

export const APP1_PLATFORM = Platform.OS;

const FETCH_PATCH_MARKER = "__grupoLuaVersionedFetchInstalled";

function inputUrl(input: VersionedFetchInput) {
  if (typeof input === "string") return input;
  if (input instanceof URL) return input.toString();
  if (input && typeof input === "object" && "url" in input) {
    return String((input as { url?: string }).url || "");
  }
  return String(input || "");
}

function inheritedHeaders(input: VersionedFetchInput) {
  if (input && typeof input === "object" && "headers" in input) {
    return (input as { headers?: HeadersInit }).headers;
  }
  return undefined;
}

export function installVersionedApiFetch() {
  const state = globalThis as typeof globalThis & Record<string, unknown>;
  if (state[FETCH_PATCH_MARKER]) return;
  state[FETCH_PATCH_MARKER] = true;

  const baseFetch = globalThis.fetch.bind(globalThis);
  globalThis.fetch = (async (input, init) => {
    const url = inputUrl(input);
    const normalizedInput = (
      input instanceof URL ? input.toString() : input
    ) as Parameters<typeof baseFetch>[0];

    if (!API_URL || !url.startsWith(API_URL)) {
      return baseFetch(normalizedInput, init);
    }

    const headers = new Headers(init?.headers || inheritedHeaders(input));
    headers.set("x-grupo-lua-app-version", APP1_VERSION);
    headers.set("x-grupo-lua-platform", APP1_PLATFORM);

    return baseFetch(normalizedInput, { ...init, headers });
  }) as typeof fetch;
}

export async function checkApp1Compatibility(): Promise<AppCompatibilityResult> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);

  try {
    const url = new URL(`${requireApiUrl()}/v1/app1/compatibility`);
    url.searchParams.set("version", APP1_VERSION);
    url.searchParams.set("platform", APP1_PLATFORM);

    const response = await fetch(url.toString(), {
      method: "GET",
      headers: { accept: "application/json" },
      signal: controller.signal
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok || data?.ok !== true) {
      throw new Error(String(data?.message || `HTTP ${response.status}`));
    }

    return data as AppCompatibilityResult;
  } finally {
    clearTimeout(timeout);
  }
}
