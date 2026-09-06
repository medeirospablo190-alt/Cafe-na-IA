import type { App1Role } from "./api";
import { SocialFeedScreenV5 } from "./SocialFeedScreenV5";

export function SocialFeedScreenV5Connected({
  sessionToken,
  deviceToken,
  fallbackProfileId = null,
  fallbackPublicName = "Lua",
  fallbackRole = "ADM",
  fallbackSessionExpiresAt = "",
  onOpenChat,
  onOpenProfile
}: {
  sessionToken: string;
  deviceToken: string;
  fallbackProfileId?: string | null;
  fallbackPublicName?: string;
  fallbackRole?: App1Role;
  fallbackSessionExpiresAt?: string;
  onOpenChat: () => void;
  onOpenProfile: () => void;
}) {
  return (
    <SocialFeedScreenV5
      sessionToken={sessionToken}
      deviceToken={deviceToken}
      viewerProfileId={fallbackProfileId}
      viewerPublicName={fallbackPublicName || "Lua"}
      viewerRole={fallbackRole}
      sessionExpiresAt={fallbackSessionExpiresAt}
      onOpenChat={onOpenChat}
      onOpenProfile={onOpenProfile}
    />
  );
}
