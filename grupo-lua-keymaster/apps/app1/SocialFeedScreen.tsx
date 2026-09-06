import type { App1Role } from "./api";
import { SocialArchive } from "./SocialArchive";
import { SocialFeedScreenV5Connected } from "./SocialFeedScreenV5Connected";

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
      <SocialFeedScreenV5Connected
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        fallbackProfileId={viewerProfileId}
        fallbackPublicName={viewerPublicName}
        fallbackRole={viewerRole}
        fallbackSessionExpiresAt={sessionExpiresAt}
        onOpenChat={onOpenChat}
        onOpenProfile={onOpenProfile}
      />
      <SocialArchive sessionToken={sessionToken} deviceToken={deviceToken} />
    </>
  );
}
