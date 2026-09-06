import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, View } from "react-native";
import { getMe, type App1Role } from "./api";
import { SocialFeedScreenV5 } from "./SocialFeedScreenV5";

type SocialIdentity = {
  profileId: string | null;
  publicName: string;
  role: App1Role;
  sessionExpiresAt: string;
};

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
  const [identity, setIdentity] = useState<SocialIdentity>({
    profileId: fallbackProfileId,
    publicName: fallbackPublicName,
    role: fallbackRole,
    sessionExpiresAt: fallbackSessionExpiresAt
  });
  const [checking, setChecking] = useState(true);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    setChecking(true);
    getMe(sessionToken, deviceToken)
      .then((result) => {
        if (!mounted.current) return;
        setIdentity({
          profileId: result.account.profileId,
          publicName: result.account.publicName || fallbackPublicName || "Lua",
          role: result.account.role,
          sessionExpiresAt: result.session.expiresAt || fallbackSessionExpiresAt
        });
      })
      .catch(() => {
        // O shell já validou a sessão. Se uma atualização de rede falhar aqui,
        // mantemos os dados já conhecidos e deixamos o próprio Social exibir
        // seus estados de indisponibilidade sem invalidar o login.
      })
      .finally(() => {
        if (mounted.current) setChecking(false);
      });

    return () => {
      mounted.current = false;
    };
  }, [sessionToken, deviceToken, fallbackProfileId, fallbackPublicName, fallbackRole, fallbackSessionExpiresAt]);

  if (checking && !identity.profileId) {
    return (
      <View style={{ minHeight: 160, alignItems: "center", justifyContent: "center" }}>
        <ActivityIndicator size="small" />
      </View>
    );
  }

  return (
    <SocialFeedScreenV5
      sessionToken={sessionToken}
      deviceToken={deviceToken}
      viewerProfileId={identity.profileId}
      viewerPublicName={identity.publicName}
      viewerRole={identity.role}
      sessionExpiresAt={identity.sessionExpiresAt}
      onOpenChat={onOpenChat}
      onOpenProfile={onOpenProfile}
    />
  );
}
