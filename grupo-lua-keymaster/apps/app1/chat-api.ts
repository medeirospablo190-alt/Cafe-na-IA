import type { App1Role } from "./api";
import { app1FeatureRequest } from "./feature-client";
import type { PublicProfileView } from "./social-api";

export type ChatMessage = {
  id: string;
  conversationId: string;
  text: string;
  mine: boolean;
  createdAt: string;
  expiresAt: string;
  sender: {
    profileId: string | null;
    publicName: string;
    role: App1Role;
    avatarStyle: string;
    frameStyle: string;
  };
};

export type ChatConversation = {
  id: string;
  createdAt: string;
  updatedAt: string;
  favorite: boolean;
  muted: boolean;
  unreadCount: number;
  other: PublicProfileView;
  latestMessage: {
    id: string;
    text: string;
    mine: boolean;
    createdAt: string;
    expiresAt: string;
  } | null;
};

export type ChatNotification = {
  id: string;
  conversationId: string;
  messageId: string | null;
  read: boolean;
  createdAt: string;
  expiresAt: string;
  preview: string;
  actor: {
    profileId: string | null;
    publicName: string;
    role: App1Role;
  } | null;
};

function jsonHeaders() {
  return { "content-type": "application/json" };
}

export async function listChats(sessionToken: string, deviceToken: string) {
  return app1FeatureRequest<{
    ok: true;
    conversations: ChatConversation[];
    unreadTotal: number;
  }>("/v1/app1/chats", sessionToken, deviceToken);
}

export async function startChat(
  sessionToken: string,
  deviceToken: string,
  profileId: string
) {
  return app1FeatureRequest<{ ok: true; conversation: ChatConversation }>(
    "/v1/app1/chats",
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ profileId }) }
  );
}

export async function listChatMessages(
  sessionToken: string,
  deviceToken: string,
  conversationId: string,
  limit = 60,
  offset = 0
) {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  return app1FeatureRequest<{
    ok: true;
    messages: ChatMessage[];
    limit: number;
    offset: number;
    hasMore: boolean;
  }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/messages?${params.toString()}`,
    sessionToken,
    deviceToken
  );
}

export async function sendChatMessage(
  sessionToken: string,
  deviceToken: string,
  conversationId: string,
  text: string
) {
  return app1FeatureRequest<{ ok: true; message: ChatMessage }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/messages`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ text }) }
  );
}

export async function markChatRead(
  sessionToken: string,
  deviceToken: string,
  conversationId: string
) {
  return app1FeatureRequest<{ ok: true; updatedCount: number }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/read`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: "{}" }
  );
}

export async function setChatFavorite(
  sessionToken: string,
  deviceToken: string,
  conversationId: string,
  favorite: boolean
) {
  return app1FeatureRequest<{ ok: true; favorite: boolean }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/favorite`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ favorite }) }
  );
}

export async function setChatMuted(
  sessionToken: string,
  deviceToken: string,
  conversationId: string,
  muted: boolean
) {
  return app1FeatureRequest<{ ok: true; muted: boolean }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/mute`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ muted }) }
  );
}

export async function reportChat(
  sessionToken: string,
  deviceToken: string,
  conversationId: string,
  reason: string
) {
  return app1FeatureRequest<{
    ok: true;
    report: { id: string; status: "OPEN" | "CLOSED"; created_at: string };
  }>(
    `/v1/app1/chats/${encodeURIComponent(conversationId)}/report`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ reason }) }
  );
}

export async function listChatNotifications(sessionToken: string, deviceToken: string) {
  return app1FeatureRequest<{
    ok: true;
    unreadCount: number;
    notifications: ChatNotification[];
  }>("/v1/app1/chat-notifications", sessionToken, deviceToken);
}
