import type { App1Role, LibraryKind } from "./api";
import { app1FeatureRequest } from "./feature-client";

export type PresenceMode = "VISIBLE" | "HIDDEN";

export type PublicProfileView = {
  profileId: string | null;
  publicName: string;
  role: App1Role;
  bio: string;
  statusText: string;
  avatarStyle: string;
  frameStyle: string;
  presenceMode: PresenceMode;
};

export type SocialPost = {
  id: string;
  kind: LibraryKind;
  comment: string | null;
  createdAt: string;
  expiresAt: string;
  pinned: boolean;
  pinnedAt: string | null;
  author: {
    profileId: string | null;
    publicName: string;
    role: App1Role;
    avatarStyle: string;
    frameStyle: string;
    statusText: string;
  };
  item: {
    id: string;
    title: string;
    content: string;
    contentBytes: number;
    truncated: boolean;
  };
  reactions: {
    likeCount: number;
    commentCount: number;
    favoriteCount: number;
    liked: boolean;
    favorited: boolean;
  };
};

export type SocialComment = {
  id: string;
  postId: string;
  parentCommentId: string | null;
  text: string;
  createdAt: string;
  editedAt: string | null;
  mine: boolean;
  author: {
    profileId: string | null;
    publicName: string;
    role: App1Role;
    avatarStyle: string;
    frameStyle: string;
    statusText: string;
  };
};

export type SocialAnnouncement = {
  id: string;
  text: string;
  createdAt: string;
  expiresAt: string;
  author: {
    profileId: string | null;
    publicName: string;
    role: "DEV";
  };
};

export type SocialNotificationKind = "LIKE" | "COMMENT" | "FAVORITE" | "ANNOUNCEMENT";

export type SocialNotification = {
  id: string;
  kind: SocialNotificationKind;
  postId: string | null;
  commentId: string | null;
  announcementId: string | null;
  read: boolean;
  createdAt: string;
  expiresAt: string;
  actor: {
    profileId: string | null;
    publicName: string;
    role: App1Role;
  } | null;
  postTitle: string | null;
};

function jsonHeaders() {
  return { "content-type": "application/json" };
}

export async function getOwnProfile(sessionToken: string, deviceToken: string) {
  return app1FeatureRequest<{ ok: true; profile: PublicProfileView }>(
    "/v1/app1/profile",
    sessionToken,
    deviceToken
  );
}

export async function updateOwnProfile(
  sessionToken: string,
  deviceToken: string,
  input: {
    bio: string;
    statusText: string;
    avatarStyle: string;
    frameStyle: string;
    presenceMode: PresenceMode;
  }
) {
  return app1FeatureRequest<{ ok: true; profile: PublicProfileView }>(
    "/v1/app1/profile",
    sessionToken,
    deviceToken,
    { method: "PATCH", headers: jsonHeaders(), body: JSON.stringify(input) }
  );
}

export async function searchPublicProfiles(
  sessionToken: string,
  deviceToken: string,
  query: string,
  limit = 20,
  offset = 0
) {
  const params = new URLSearchParams({ q: query, limit: String(limit), offset: String(offset) });
  return app1FeatureRequest<{
    ok: true;
    profiles: PublicProfileView[];
    total: number;
    limit: number;
    offset: number;
    hasMore: boolean;
  }>(`/v1/app1/social/profiles?${params.toString()}`, sessionToken, deviceToken);
}

export async function getPublicProfile(sessionToken: string, deviceToken: string, profileId: string) {
  return app1FeatureRequest<{
    ok: true;
    profile: PublicProfileView;
    counts: { posts: number; favorites: number };
  }>(`/v1/app1/social/profiles/${encodeURIComponent(profileId)}`, sessionToken, deviceToken);
}

export async function getProfilePosts(sessionToken: string, deviceToken: string, profileId: string) {
  return app1FeatureRequest<{ ok: true; posts: SocialPost[] }>(
    `/v1/app1/social/profiles/${encodeURIComponent(profileId)}/posts`,
    sessionToken,
    deviceToken
  );
}

export async function getProfileFavorites(sessionToken: string, deviceToken: string, profileId: string) {
  return app1FeatureRequest<{ ok: true; posts: SocialPost[] }>(
    `/v1/app1/social/profiles/${encodeURIComponent(profileId)}/favorites`,
    sessionToken,
    deviceToken
  );
}

export async function listSocialFeed(
  sessionToken: string,
  deviceToken: string,
  limit = 30,
  offset = 0
) {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  return app1FeatureRequest<{
    ok: true;
    posts: SocialPost[];
    announcements: SocialAnnouncement[];
    limit: number;
    offset: number;
    hasMore: boolean;
  }>(`/v1/app1/social/feed?${params.toString()}`, sessionToken, deviceToken);
}

export async function getSocialPost(sessionToken: string, deviceToken: string, postId: string) {
  return app1FeatureRequest<{ ok: true; post: SocialPost }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}`,
    sessionToken,
    deviceToken
  );
}

export async function setSocialLike(
  sessionToken: string,
  deviceToken: string,
  postId: string,
  liked: boolean
) {
  return app1FeatureRequest<{ ok: true; liked: boolean; likeCount: number; changed: boolean }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/like`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ liked }) }
  );
}

export async function setSocialFavorite(
  sessionToken: string,
  deviceToken: string,
  postId: string,
  favorite: boolean
) {
  return app1FeatureRequest<{ ok: true; favorite: boolean; favoriteCount: number; changed: boolean }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/favorite`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ favorite }) }
  );
}

export async function listPostFavorites(sessionToken: string, deviceToken: string, postId: string) {
  return app1FeatureRequest<{ ok: true; profiles: PublicProfileView[] }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/favorites`,
    sessionToken,
    deviceToken
  );
}

export async function listSocialComments(
  sessionToken: string,
  deviceToken: string,
  postId: string,
  limit = 30,
  offset = 0
) {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  return app1FeatureRequest<{
    ok: true;
    comments: SocialComment[];
    limit: number;
    offset: number;
    hasMore: boolean;
  }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/comments?${params.toString()}`,
    sessionToken,
    deviceToken
  );
}

export async function createSocialComment(
  sessionToken: string,
  deviceToken: string,
  postId: string,
  text: string,
  parentCommentId?: string | null
) {
  return app1FeatureRequest<{ ok: true; comment: SocialComment }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/comments`,
    sessionToken,
    deviceToken,
    {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ text, parentCommentId: parentCommentId || null })
    }
  );
}

export async function deleteSocialComment(
  sessionToken: string,
  deviceToken: string,
  commentId: string
) {
  return app1FeatureRequest<{ ok: true; deleted: true }>(
    `/v1/app1/social/comments/${encodeURIComponent(commentId)}`,
    sessionToken,
    deviceToken,
    { method: "DELETE" }
  );
}

export async function setSocialPostPinned(
  sessionToken: string,
  deviceToken: string,
  postId: string,
  pinned: boolean
) {
  return app1FeatureRequest<{ ok: true; pinned: boolean; replacedPostId: string | null }>(
    `/v1/app1/social/posts/${encodeURIComponent(postId)}/pin`,
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ pinned }) }
  );
}

export async function listSocialNotifications(
  sessionToken: string,
  deviceToken: string,
  kind?: SocialNotificationKind
) {
  const suffix = kind ? `?kind=${encodeURIComponent(kind)}` : "";
  return app1FeatureRequest<{
    ok: true;
    unread: Record<"ALL" | SocialNotificationKind, number>;
    notifications: SocialNotification[];
  }>(`/v1/app1/social/notifications${suffix}`, sessionToken, deviceToken);
}

export async function markSocialNotificationsRead(
  sessionToken: string,
  deviceToken: string,
  input: { ids?: string[]; kind?: SocialNotificationKind }
) {
  return app1FeatureRequest<{ ok: true; updatedCount: number }>(
    "/v1/app1/social/notifications/read",
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify(input) }
  );
}

export async function createGlobalAnnouncement(sessionToken: string, deviceToken: string, text: string) {
  return app1FeatureRequest<{
    ok: true;
    announcement: { id: string; text: string; createdAt: string; expiresAt: string };
  }>(
    "/v1/app1/social/announcements",
    sessionToken,
    deviceToken,
    { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ text }) }
  );
}

export async function updateGlobalAnnouncement(
  sessionToken: string,
  deviceToken: string,
  announcementId: string,
  text: string
) {
  return app1FeatureRequest<{
    ok: true;
    announcement: { id: string; text: string; createdAt: string; expiresAt: string };
  }>(
    `/v1/app1/social/announcements/${encodeURIComponent(announcementId)}`,
    sessionToken,
    deviceToken,
    { method: "PATCH", headers: jsonHeaders(), body: JSON.stringify({ text }) }
  );
}
