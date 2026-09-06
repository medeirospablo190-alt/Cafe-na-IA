import * as FileSystem from "expo-file-system/legacy";
import { App1ApiError, type App1Role } from "./api";
import { requireApiUrl } from "./config";
import { app1AuthHeaders, app1FeatureRequest } from "./feature-client";

export type SocialPhotoStatus = {
  id: string;
  createdAt: string;
  expiresAt: string;
  mine: boolean;
};

export type SocialStatusProfile = {
  profileId: string | null;
  publicName: string;
  role: App1Role;
  avatarStyle: string;
  frameStyle: string;
  statusText: string;
  mine: boolean;
  activeStatus: SocialPhotoStatus | null;
};

export async function listSocialStatuses(sessionToken: string, deviceToken: string) {
  return app1FeatureRequest<{ ok: true; profiles: SocialStatusProfile[] }>(
    "/v1/app1/social/statuses",
    sessionToken,
    deviceToken
  );
}

export function socialStatusImageSource(
  statusId: string,
  sessionToken: string,
  deviceToken: string
) {
  return {
    uri: `${requireApiUrl()}/v1/app1/social/statuses/${encodeURIComponent(statusId)}/image`,
    headers: app1AuthHeaders(sessionToken, deviceToken)
  };
}

export async function uploadSocialStatus(
  sessionToken: string,
  deviceToken: string,
  fileUri: string,
  mimeType: string
) {
  const normalizedMime = String(mimeType || "").split(";")[0].trim().toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(normalizedMime)) {
    throw new App1ApiError("Use uma foto JPG, PNG ou WEBP.", 415, "STATUS_IMAGE_TYPE_UNSUPPORTED");
  }

  const info = await FileSystem.getInfoAsync(fileUri);
  if (!info.exists) {
    throw new App1ApiError("A foto escolhida não está mais disponível.", 400, "STATUS_IMAGE_MISSING");
  }
  const size = "size" in info && typeof info.size === "number" ? info.size : 0;
  if (size <= 0) {
    throw new App1ApiError("A foto escolhida está vazia.", 400, "STATUS_IMAGE_EMPTY");
  }
  if (size > 4 * 1024 * 1024) {
    throw new App1ApiError("A foto do status pode ter no máximo 4 MB.", 413, "STATUS_IMAGE_TOO_LARGE");
  }

  const result = await FileSystem.uploadAsync(
    `${requireApiUrl()}/v1/app1/social/statuses`,
    fileUri,
    {
      httpMethod: "POST",
      uploadType: FileSystem.FileSystemUploadType.BINARY_CONTENT,
      headers: {
        ...app1AuthHeaders(sessionToken, deviceToken),
        "content-type": normalizedMime
      }
    }
  );

  let data: any = {};
  try {
    data = result.body ? JSON.parse(result.body) : {};
  } catch {
    data = {};
  }
  if (result.status < 200 || result.status >= 300) {
    throw new App1ApiError(
      String(data?.message || `HTTP ${result.status}`),
      result.status,
      String(data?.code || "STATUS_UPLOAD_FAILED")
    );
  }
  return data as { ok: true; status: SocialPhotoStatus };
}

export async function deleteSocialStatus(
  sessionToken: string,
  deviceToken: string,
  statusId: string
) {
  return app1FeatureRequest<{ ok: true; deleted: true }>(
    `/v1/app1/social/statuses/${encodeURIComponent(statusId)}`,
    sessionToken,
    deviceToken,
    { method: "DELETE" }
  );
}
