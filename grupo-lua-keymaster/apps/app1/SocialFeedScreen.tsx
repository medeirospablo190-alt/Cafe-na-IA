import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
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
  const [archiveOpen, setArchiveOpen] = useState(false);

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

      <View style={styles.archiveArea}>
        <Pressable
          style={styles.archiveToggle}
          onPress={() => setArchiveOpen((value) => !value)}
          accessibilityRole="button"
          accessibilityLabel={archiveOpen ? "Fechar arquivo social" : "Abrir arquivo social"}
          accessibilityState={{ expanded: archiveOpen }}
        >
          <Text style={styles.archiveToggleText}>{archiveOpen ? "FECHAR ARQUIVO" : "ARQUIVO SOCIAL"}</Text>
          <View style={[styles.archiveChevron, archiveOpen && styles.archiveChevronOpen]} />
        </Pressable>
        {archiveOpen ? (
          <View style={styles.archivePanel}>
            <SocialArchive sessionToken={sessionToken} deviceToken={deviceToken} />
          </View>
        ) : null}
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  archiveArea: { marginTop: 6, marginBottom: 10, marginHorizontal: 2 },
  archiveToggle: {
    minHeight: 39,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(5,5,8,0.18)",
    paddingHorizontal: 12,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between"
  },
  archiveToggleText: { color: "rgba(235,235,240,0.68)", fontSize: 8, fontWeight: "900", letterSpacing: 0.7 },
  archiveChevron: {
    width: 8,
    height: 8,
    borderRightWidth: 1.5,
    borderBottomWidth: 1.5,
    borderColor: "rgba(235,235,240,0.62)",
    transform: [{ rotate: "45deg" }, { translateY: -2 }]
  },
  archiveChevronOpen: {
    transform: [{ rotate: "225deg" }, { translateY: -2 }]
  },
  archivePanel: {
    marginTop: 6,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.12)",
    backgroundColor: "rgba(3,3,6,0.20)",
    padding: 7,
    overflow: "hidden"
  }
});