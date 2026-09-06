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
  listSocialFeed,
  updateGlobalAnnouncement
} from "./social-api";

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function PlusIcon() {
  return (
    <View style={s.iconBox}>
      <View style={s.plusHorizontal} />
      <View style={s.plusVertical} />
    </View>
  );
}

function CloseIcon() {
  return (
    <View style={s.iconBox}>
      <View style={[s.closeStroke, { transform: [{ rotate: "45deg" }] }]} />
      <View style={[s.closeStroke, { transform: [{ rotate: "-45deg" }] }]} />
    </View>
  );
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
  const [editing, setEditing] = useState<SocialAnnouncement | null>(null);
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

  function openNewComposer() {
    if (viewerRole !== "DEV" || busy) return;
    setEditing(null);
    setDraft("");
    setComposerOpen(true);
  }

  function openEditComposer(item: SocialAnnouncement) {
    if (viewerRole !== "DEV" || busy) return;
    setEditing(item);
    setDraft(item.text);
    setComposerOpen(true);
  }

  function closeComposer() {
    if (busy) return;
    setComposerOpen(false);
    setEditing(null);
    setDraft("");
  }

  async function saveAnnouncement() {
    const text = draft.trim();
    if (viewerRole !== "DEV" || !text || busy) return;
    setBusy(true);
    try {
      if (editing) {
        await updateGlobalAnnouncement(sessionToken, deviceToken, editing.id, text);
      } else {
        await createGlobalAnnouncement(sessionToken, deviceToken, text);
      }
      if (!mounted.current) return;
      setDraft("");
      setEditing(null);
      setComposerOpen(false);
      await reload(false);
    } catch (error) {
      if (mounted.current) {
        Alert.alert(
          editing ? "Não foi possível editar" : "Não foi possível publicar",
          error instanceof Error ? error.message : editing ? "Falha ao editar o aviso." : "Falha ao publicar o aviso."
        );
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
          <Text style={s.subtitle}>Avisos oficiais dos desenvolvedores</Text>
        </View>
        {viewerRole === "DEV" ? (
          <Pressable
            style={s.devButton}
            onPress={openNewComposer}
            accessibilityRole="button"
            accessibilityLabel="Publicar aviso DEV"
          >
            <PlusIcon />
          </Pressable>
        ) : null}
      </View>

      <View style={s.headerDivider} />

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
        <View key={item.id} style={s.post}>
          <View style={s.cardHead}>
            <View style={s.devMark}><Text style={s.devMarkText}>DEV</Text></View>
            <View style={s.identity}>
              <Text style={s.author}>{item.author.publicName || "GRUPO LUA"}</Text>
              <Text style={s.date}>{dateText(item.createdAt)}</Text>
            </View>
            {viewerRole === "DEV" ? (
              <Pressable
                style={s.editButton}
                disabled={busy}
                onPress={() => openEditComposer(item)}
                accessibilityRole="button"
                accessibilityLabel={`Editar aviso de ${item.author.publicName || "DEV"}`}
              >
                <Text style={s.editText}>EDITAR</Text>
              </Pressable>
            ) : null}
          </View>
          <Text style={s.body}>{item.text}</Text>
        </View>
      )) : null}

      <Modal
        visible={composerOpen}
        transparent
        animationType="fade"
        onRequestClose={closeComposer}
      >
        <KeyboardAvoidingView style={s.backdrop} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <View style={s.modalBox}>
            <View style={s.modalHeader}>
              <View style={{ flex: 1 }}>
                <Text style={s.modalTitle}>{editing ? "Editar aviso" : "Novo aviso"}</Text>
                {editing ? <Text style={s.modalMeta}>O prazo original do aviso será mantido.</Text> : null}
              </View>
              <Pressable
                disabled={busy}
                style={s.closeButton}
                onPress={closeComposer}
                accessibilityRole="button"
                accessibilityLabel="Fechar"
              >
                <CloseIcon />
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
              placeholderTextColor="rgba(230,230,236,0.50)"
              style={s.input}
            />
            <Pressable
              disabled={!draft.trim() || busy}
              style={[s.publish, (!draft.trim() || busy) && s.disabled]}
              onPress={() => saveAnnouncement().catch(() => {})}
            >
              <Text style={s.publishText}>
                {busy ? "SALVANDO..." : editing ? "SALVAR ALTERAÇÕES" : "PUBLICAR"}
              </Text>
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  header: { flexDirection: "row", alignItems: "center", gap: 12, marginHorizontal: -2, paddingHorizontal: 2, paddingTop: 2, paddingBottom: 10 },
  headerText: { flex: 1 },
  title: { color: "#FFFFFF", fontSize: 20, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.62)", fontSize: 9, marginTop: 3 },
  headerDivider: { height: StyleSheet.hairlineWidth, backgroundColor: "rgba(255,255,255,0.14)", marginHorizontal: -12 },
  iconBox: { width: 22, height: 22, alignItems: "center", justifyContent: "center", position: "relative" },
  plusHorizontal: { position: "absolute", width: 13, height: 1.8, borderRadius: 1, backgroundColor: "#FFFFFF" },
  plusVertical: { position: "absolute", width: 1.8, height: 13, borderRadius: 1, backgroundColor: "#FFFFFF" },
  closeStroke: { position: "absolute", width: 14, height: 1.6, borderRadius: 1, backgroundColor: "#FFFFFF" },
  devButton: {
    width: 42,
    height: 42,
    borderRadius: 12,
    backgroundColor: "rgba(185,20,30,0.90)",
    borderWidth: 1,
    borderColor: "rgba(255,100,108,0.48)",
    alignItems: "center",
    justifyContent: "center"
  },
  loader: { marginVertical: 26 },
  messageCard: {
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.24)",
    padding: 12,
    marginTop: 10
  },
  message: { color: "#F1D9DB", fontSize: 10, lineHeight: 16 },
  retry: { color: "#FF777D", fontSize: 7, fontWeight: "900", marginTop: 7 },
  empty: {
    paddingVertical: 42,
    paddingHorizontal: 20,
    alignItems: "center"
  },
  emptyTitle: { color: "#FFFFFF", fontSize: 14, fontWeight: "900", textAlign: "center" },
  emptyText: { color: "rgba(235,235,240,0.60)", fontSize: 9, lineHeight: 15, textAlign: "center", marginTop: 6 },
  post: {
    marginHorizontal: -12,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(3,3,5,0.06)",
    paddingHorizontal: 14,
    paddingVertical: 14
  },
  cardHead: { flexDirection: "row", alignItems: "center", gap: 9 },
  devMark: {
    minWidth: 36,
    height: 27,
    borderRadius: 7,
    backgroundColor: "rgba(151,15,24,0.68)",
    borderWidth: 1,
    borderColor: "rgba(255,88,98,0.38)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 7
  },
  devMarkText: { color: "#FFB1B5", fontSize: 7, fontWeight: "900" },
  identity: { flex: 1 },
  author: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  date: { color: "rgba(225,225,232,0.56)", fontSize: 8, marginTop: 2 },
  editButton: {
    minHeight: 30,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "rgba(255,94,103,0.36)",
    backgroundColor: "rgba(74,10,14,0.20)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 9
  },
  editText: { color: "#FF9DA2", fontSize: 7, fontWeight: "900" },
  body: { color: "#F2F2F5", fontSize: 12, lineHeight: 19, marginTop: 11 },
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.68)", justifyContent: "center", padding: 16 },
  modalBox: {
    width: "100%",
    maxWidth: 540,
    alignSelf: "center",
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(8,8,10,0.88)",
    padding: 15
  },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  modalTitle: { color: "#FFFFFF", fontSize: 17, fontWeight: "900" },
  modalMeta: { color: "rgba(235,235,240,0.56)", fontSize: 8, lineHeight: 13, marginTop: 3 },
  closeButton: { width: 36, height: 36, alignItems: "center", justifyContent: "center" },
  input: {
    minHeight: 130,
    maxHeight: 240,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(0,0,0,0.26)",
    color: "#FFFFFF",
    paddingHorizontal: 12,
    paddingVertical: 11,
    marginTop: 12
  },
  publish: {
    minHeight: 48,
    borderRadius: 11,
    backgroundColor: "#B51D25",
    alignItems: "center",
    justifyContent: "center",
    marginTop: 12
  },
  publishText: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  disabled: { opacity: 0.42 }
});
