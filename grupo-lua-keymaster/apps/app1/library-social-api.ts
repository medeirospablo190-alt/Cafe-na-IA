import { App1ApiError, type LibraryKind } from "./api";
import { requireApiUrl } from "./config";

const API_TIMEOUT_MS = 45_000;

export type FeedPostWithComment = {
  id: string;
  kind: LibraryKind;
  comment: string | null;
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

function authHeaders(sessionToken: string, deviceToken: string) {
  return {
    authorization: `Bearer ${sessionToken}`,
    "x-app1-device-token": deviceToken
  };
}

async function request<T>(path: string, init: RequestInit = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  let response: Response;

  try {
    response = await fetch(`${requireApiUrl()}${path}`, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new App1ApiError(
        "O servidor demorou demais para responder. Verifique sua conexão e tente novamente.",
        0,
        "NETWORK_TIMEOUT"
      );
    }
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

export async function shareLibraryItemWithComment(
  sessionToken: string,
  deviceToken: string,
  id: string,
  comment: string,
  favorite?: boolean
) {
  return request<{
    ok: true;
    favorite: boolean;
    post: {
      id: string;
      post_kind: LibraryKind;
      comment_text: string | null;
      created_at: string;
      expires_at: string;
    };
  }>(`/v1/app1/library/${encodeURIComponent(id)}/share/options`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...authHeaders(sessionToken, deviceToken)
    },
    body: JSON.stringify({ comment, ...(favorite === undefined ? {} : { favorite }) })
  });
}

export async function listFeedPostsWithComments(sessionToken: string, deviceToken: string) {
  return request<{ ok: true; posts: FeedPostWithComment[] }>("/v1/app1/feed", {
    headers: authHeaders(sessionToken, deviceToken)
  });
}

export async function getFeedPostWithComments(sessionToken: string, deviceToken: string, id: string) {
  return request<{ ok: true; post: FeedPostWithComment }>(`/v1/app1/feed/${encodeURIComponent(id)}`, {
    headers: authHeaders(sessionToken, deviceToken)
  });
}
