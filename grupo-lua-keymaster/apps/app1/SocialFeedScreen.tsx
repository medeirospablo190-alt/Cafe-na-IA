import type { App1Role } from "./api";
import { SocialArchive } from "./SocialArchive";
import { SocialFeedScreenV4 } from "./SocialFeedScreenV4";

export function SocialFeedScreen({
  sessionToken,
  deviceToken,
  viewerRole = "ADM",
  onOpenChat = () => {},
  onOpenProfile = () => {}
}: {
  sessionToken: string;
  deviceToken: string;
  viewerRole?: App1Role;
  onOpenChat?: () => void;
  onOpenProfile?: () => void;
}) {
  return (
    <>
      <SocialFeedScreenV4
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        viewerRole={viewerRole}
        onOpenChat={onOpenChat}
        onOpenProfile={onOpenProfile}
      />
      <SocialArchive sessionToken={sessionToken} deviceToken={deviceToken} />
    </>
  );
}
