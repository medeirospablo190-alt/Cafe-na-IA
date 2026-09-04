import type { App1Role } from "./api";
import { SocialArchive } from "./SocialArchive";
import { SocialFeedScreen as SocialFeedScreenV3 } from "./SocialFeedScreenV3";

export function SocialFeedScreen({
  sessionToken,
  deviceToken,
  viewerRole = "ADM"
}: {
  sessionToken: string;
  deviceToken: string;
  viewerRole?: App1Role;
}) {
  return (
    <>
      <SocialFeedScreenV3
        sessionToken={sessionToken}
        deviceToken={deviceToken}
        viewerRole={viewerRole}
      />
      <SocialArchive sessionToken={sessionToken} deviceToken={deviceToken} />
    </>
  );
}
