import { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import type { App1Role } from "./api";
import {
  type SocialAnnouncement,
  createGlobalAnnouncement,
  listSocialFeed
} from "./social-api";

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function DevUpdatesHome({
  sessionToken,
  deviceToken,
  viewerRole
}: {
  sessionToken: string;
  deviceToken: string;
  viewerRole: App1Role;
}) {
  const [items, setItems] = useState<SocialAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [composerOpen, setComposerOpen] = useState(false);
  const [draft, setDraft] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const mounted = useRef(true);

  async function reload(showSpinner = true) {
    if (showSpinner) setLoading(true);
    setMessage(null);
    try {
      const result = await listSocialFeed(sessionToken, deviceToken, 1, 0);
      if (mounted.current) setItems(result.announcements);
    } catch (error) {
      if (mounted.current) {
        setMessage(error instanceof Error ? error.message : "Não foi possível carregar os avisos.");
      }
    } finally {
      if (mounted.current && showSpinner) setLoading(false);
    }
  }

  async function publish() {
    const text = draft.trim();
    if (viewerRole !== "DEV" || !text || busy) return;
    setBusy(true);
    try {
      await createGlobalAnnouncement(sessionToken, deviceToken, text);
      if (!mounted.current) return;
      setDraft("");
      setComposerOpen(false);
      await reload(false);
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Não foi possível publicar", error instanceof Error ? error.message : "Falha ao publicar o aviso.");
      }
    } finally {
      if (mounted.current) setBusy(false);
    }
  }

  useEffect(() => {
    mounted.current = true;
    reload(true).catch(() => {});
    return () => {
      mounted.current = false;
    };
  }, [sessionToken, deviceToken]);

  return (
    <View style={s.root}>
      <View style={s.header}>
        <View style={s.headerText}>
          <Text style={s.title}>Atualizações</Text>
          <Text style={s.subtitle}>Publicações oficiais dos desenvolvedores.</Text>
        </View>
        {viewerRole === "DEV" ? (
          <Pressable
            style={s.devButton}
            onPress={() => setComposerOpen(true)}
            accessibilityRole="button"
            accessibilityLabel="Publicar aviso DEV"
          >
            <Text style={s.devButtonText}>＋</Text>
          </Pressable>
        ) : null}
      </View>

      {message ? (
        <Pressable style={s.messageCard} onPress={() => reload(true).catch(() => {})}>
          <Text style={s.message}>{message}</Text>
          <Text style={s.retry}>TOCAR PARA TENTAR NOVAMENTE</Text>
        </Pressable>
      ) : null}

      {loading ? <ActivityIndicator style={s.loader} /> : null}

      {!loading && items.length === 0 ? (
        <View style={s.empty}>
          <Text style={s.emptyTitle}>Nenhuma atualização publicada</Text>
          <Text style={s.emptyText}>Quando um DEV publicar um aviso, ele aparecerá aqui com a data da publicação.</Text>
        </View>
      ) : null}

      {!loading ? items.map((item) => (
        <View key={item.id} style={s.card}>
          <View style={s.cardHead}>
            <View style={s.devMark}><Text style={s.devMarkText}>DEV</Text></View>
            <View style={s.identity}>
              <Text style={s.author}>{item.author.publicName || "GRUPO LUA"}</Text>
              <Text style={s.date}>{dateText(item.createdAt)}</Text>
            </View>
          </View>
          <Text style={s.body}>{item.text}</Text>
        </View>
      )) : null}

      <Modal
        visible={composerOpen}
        transparent
        animationType="fade"
        onRequestClose={() => { if (!busy) setComposerOpen(false); }}
      >
        <KeyboardAvoidingView style={s.backdrop} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <View style={s.modalBox}>
            <View style={s.modalHeader}>
              <Text style={s.modalTitle}>Novo aviso</Text>
              <Pressable disabled={busy} onPress={() => setComposerOpen(false)}>
                <Text style={s.close}>✕</Text>
              </Pressable>
            </View>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              editable={!busy}
              multiline
              maxLength={1000}
              textAlignVertical="top"
              placeholder="Escreva o aviso..."
              placeholderTextColor="#A2A2A8"
              style={s.input}
            />
            <Pressable
              disabled={!draft.trim() || busy}
              style={[s.publish, (!draft.trim() || busy) && s.disabled]}
              onPress={() => publish().catch(() => {})}
            >
              <Text style={s.publishText}>{busy ? "PUBLICANDO..." : "PUBLICAR"}</Text>
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  header: { flexDirection: "row", alignItems: "center", gap: 12, marginBottom: 12 },
  headerText: { flex: 1 },
  title: { color: "#FFFFFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.72)", fontSize: 10, marginTop: 3 },
  devButton: {
    width: 44,
    height: 44,
    borderRadius: 14,
    backgroundColor: "rgba(192,26,34,0.94)",
    borderWidth: 1,
    borderColor: "rgba(255,110,116,0.58)",
    alignItems: "center",
    justifyContent: "center"
  },
  devButtonText: { color: "#FFFFFF", fontSize: 25, lineHeight: 27, fontWeight: "500" },
  loader: { marginVertical: 26 },
  messageCard: {
    borderRadius: 15,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(5,5,7,0.34)",
    padding: 13,
    marginBottom: 10
  },
  message: { color: "#F1D9DB", fontSize: 11, lineHeight: 17 },
  retry: { color: "#FF777D", fontSize: 7, fontWeight: "900", marginTop: 7 },
  empty: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.28)",
    padding: 24,
    alignItems: "center"
  },
  emptyTitle: { color: "#FFFFFF", fontSize: 15, fontWeight: "900", textAlign: "center" },
  emptyText: { color: "rgba(235,235,240,0.68)", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 6 },
  card: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(5,5,7,0.32)",
    padding: 14,
    marginBottom: 10
  },
  cardHead: { flexDirection: "row", alignItems: "center", gap: 9 },
  devMark: {
    minWidth: 38,
    height: 30,
    borderRadius: 10,
    backgroundColor: "rgba(163,20,27,0.78)",
    borderWidth: 1,
    borderColor: "rgba(255,105,111,0.45)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 7
  },
  devMarkText: { color: "#FFB1B5", fontSize: 8, fontWeight: "900" },
  identity: { flex: 1 },
  author: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  date: { color: "rgba(225,225,232,0.58)", fontSize: 8, marginTop: 2 },
  body: { color: "#F2F2F5", fontSize: 12, lineHeight: 19, marginTop: 12 },
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.64)", justifyContent: "center", padding: 16 },
  modalBox: {
    width: "100%",
    maxWidth: 540,
    alignSelf: "center",
    borderRadius: 20,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(8,8,10,0.86)",
    padding: 15
  },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  modalTitle: { color: "#FFFFFF", fontSize: 17, fontWeight: "900" },
  close: { color: "#D0D0D5", fontSize: 18, padding: 5 },
  input: {
    minHeight: 130,
    maxHeight: 240,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(0,0,0,0.28)",
    color: "#FFFFFF",
    paddingHorizontal: 12,
    paddingVertical: 11,
    marginTop: 12
  },
  publish: {
    minHeight: 48,
    borderRadius: 12,
    backgroundColor: "#B51D25",
    alignItems: "center",
    justifyContent: "center",
    marginTop: 12
  },
  publishText: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  disabled: { opacity: 0.42 }
});
