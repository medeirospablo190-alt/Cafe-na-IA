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
        <Pressable style={styles.archiveToggle} onPress={() => setArchiveOpen((value) => !value)}>
          <Text style={styles.archiveToggleText}>{archiveOpen ? "FECHAR ARQUIVO" : "ARQUIVO SOCIAL"}</Text>
          <Text style={styles.archiveToggleGlyph}>{archiveOpen ? "⌃" : "⌄"}</Text>
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
  archiveArea: { marginTop: 8, marginBottom: 12 },
  archiveToggle: {
    minHeight: 42,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(123,123,136,0.30)",
    backgroundColor: "rgba(7,7,10,0.30)",
    paddingHorizontal: 13,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between"
  },
  archiveToggleText: { color: "#B9B9C1", fontSize: 8, fontWeight: "900", letterSpacing: 0.8 },
  archiveToggleGlyph: { color: "#9D9DA5", fontSize: 15, fontWeight: "900" },
  archivePanel: {
    marginTop: 7,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(108,108,120,0.24)",
    backgroundColor: "rgba(5,5,8,0.24)",
    padding: 8,
    overflow: "hidden"
  }
});