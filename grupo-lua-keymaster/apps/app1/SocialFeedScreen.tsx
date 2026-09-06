import type { App1Role } from "./api";
import { SocialArchive } from "./SocialArchive";
import { SocialFeedScreenV5 } from "./SocialFeedScreenV5";

export function SocialFeedScreen({
  sessionToken,
  deviceToken,
  viewerProfileId = null,
  viewerPublicName = "Lua",
  viewerRole = "ADM",
  sessionExpiresAt = "",
  onOpenChat = () => {},
  onOpenProfile = () => {}
}: {
  sessionToken: string;
  deviceToken: string;
  viewerProfileId?: string | null;
  viewerPublicName?: string;
  viewerRole?: App1Role;
  sessionExpiresAt?: string;
  onOpenChat?: () => void;
  onOpenProfile?: () => void;
}) {
  return (
    <>
      <SocialFeedScreenV5
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        viewerProfileId={viewerProfileId}
        viewerPublicName={viewerPublicName}
        viewerRole={viewerRole}
        sessionExpiresAt={sessionExpiresAt}
        onOpenChat={onOpenChat}
        onOpenProfile={onOpenProfile}
      />
      <SocialArchive sessionToken={sessionToken} deviceToken={deviceToken} />
    </>
  );
}
