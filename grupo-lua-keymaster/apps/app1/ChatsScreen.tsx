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
import {
  type ChatConversation,
  type ChatMessage,
  listChatMessages,
  listChats,
  markChatRead,
  reportChat,
  sendChatMessage,
  setChatFavorite,
  setChatMuted,
  startChat
} from "./chat-api";
import { type PublicProfileView, searchPublicProfiles } from "./social-api";

const MESSAGE_PAGE_SIZE = 100;

function dateText(value?: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function expiryText(value?: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const ms = date.getTime() - Date.now();
  if (ms <= 0) return "expirada";
  const hours = Math.ceil(ms / 3_600_000);
  return hours <= 24 ? `${hours}h restantes` : date.toLocaleDateString("pt-BR");
}

function timeValue(value?: string | null) {
  if (!value) return 0;
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

function ChevronIcon() {
  return <View style={s.chevronIcon} />;
}

export function ChatsScreen({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [selected, setSelected] = useState<ChatConversation | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [hasOlderMessages, setHasOlderMessages] = useState(false);
  const [busy, setBusy] = useState(false);
  const [draft, setDraft] = useState("");
  const [search, setSearch] = useState("");
  const [profiles, setProfiles] = useState<PublicProfileView[]>([]);
  const [searching, setSearching] = useState(false);
  const [reportOpen, setReportOpen] = useState(false);
  const [reportReason, setReportReason] = useState("");
  const [unreadTotal, setUnreadTotal] = useState(0);
  const mounted = useRef(true);
  const mutationLock = useRef(false);
  const conversationVersion = useRef(0);
  const loadedMessageCount = useRef(0);
  const loadingOlderRef = useRef(false);

  function beginMutation() {
    if (mutationLock.current) return false;
    mutationLock.current = true;
    setBusy(true);
    return true;
  }

  function endMutation() {
    mutationLock.current = false;
    if (mounted.current) setBusy(false);
  }

  async function reloadConversations(showSpinner = false) {
    if (showSpinner) setLoading(true);
    try {
      const result = await listChats(sessionToken, deviceToken);
      if (!mounted.current) return;
      setConversations(result.conversations);
      setUnreadTotal(result.unreadTotal);
      if (selected) {
        const fresh = result.conversations.find((item) => item.id === selected.id) || null;
        if (fresh) setSelected(fresh);
      }
    } catch (error) {
      if (showSpinner && mounted.current) {
        Alert.alert("Chats indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar as conversas.");
      }
    } finally {
      if (showSpinner && mounted.current) setLoading(false);
    }
  }

  async function reloadMessages(
    conversation: ChatConversation,
    showSpinner = false,
    preserveOlder = false
  ) {
    const version = ++conversationVersion.current;
    if (showSpinner) setMessagesLoading(true);
    try {
      const result = await listChatMessages(
        sessionToken,
        deviceToken,
        conversation.id,
        MESSAGE_PAGE_SIZE,
        0
      );
      if (!mounted.current || version !== conversationVersion.current) return;

      setMessages((current) => {
        if (!preserveOlder || current.length <= MESSAGE_PAGE_SIZE) {
          loadedMessageCount.current = result.messages.length;
          return result.messages;
        }

        const firstRecentTime = timeValue(result.messages[0]?.createdAt);
        const recentIds = new Set(result.messages.map((item) => item.id));
        const older = current.filter((item) => {
          if (recentIds.has(item.id)) return false;
          return firstRecentTime > 0 && timeValue(item.createdAt) < firstRecentTime;
        });
        const merged = [...older, ...result.messages];
        loadedMessageCount.current = merged.length;
        return merged;
      });

      if (!preserveOlder || loadedMessageCount.current <= MESSAGE_PAGE_SIZE) {
        setHasOlderMessages(result.hasMore);
      }

      await markChatRead(sessionToken, deviceToken, conversation.id).catch(() => {});
      if (!mounted.current || version !== conversationVersion.current) return;
      setUnreadTotal((current) => Math.max(0, current - conversation.unreadCount));
      setConversations((current) => current.map((item) => item.id === conversation.id ? { ...item, unreadCount: 0 } : item));
      setSelected((current) => current?.id === conversation.id ? { ...current, unreadCount: 0 } : current);
    } catch (error) {
      if (showSpinner && mounted.current) {
        Alert.alert("Mensagens indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar o chat.");
      }
    } finally {
      if (showSpinner && mounted.current && version === conversationVersion.current) setMessagesLoading(false);
    }
  }

  async function loadOlderMessages() {
    if (!selected || loadingOlderRef.current || !hasOlderMessages) return;
    loadingOlderRef.current = true;
    setLoadingOlder(true);
    const version = conversationVersion.current;
    const offset = loadedMessageCount.current || messages.length;
    try {
      const result = await listChatMessages(
        sessionToken,
        deviceToken,
        selected.id,
        MESSAGE_PAGE_SIZE,
        offset
      );
      if (!mounted.current || version !== conversationVersion.current) return;

      setMessages((current) => {
        const currentIds = new Set(current.map((item) => item.id));
        const olderUnique = result.messages.filter((item) => !currentIds.has(item.id));
        const merged = [...olderUnique, ...current];
        loadedMessageCount.current = merged.length;
        return merged;
      });
      setHasOlderMessages(result.hasMore);
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Histórico indisponível", error instanceof Error ? error.message : "Não foi possível carregar mensagens mais antigas.");
      }
    } finally {
      loadingOlderRef.current = false;
      if (mounted.current && version === conversationVersion.current) setLoadingOlder(false);
    }
  }

  async function openConversation(conversation: ChatConversation) {
    setSelected(conversation);
    setMessages([]);
    loadedMessageCount.current = 0;
    setHasOlderMessages(false);
    setDraft("");
    await reloadMessages(conversation, true, false);
  }

  async function startWithProfile(profile: PublicProfileView) {
    if (!profile.profileId || !beginMutation()) return;
    try {
      const result = await startChat(sessionToken, deviceToken, profile.profileId);
      if (!mounted.current) return;
      setSearch("");
      setProfiles([]);
      await reloadConversations(false);
      await openConversation(result.conversation);
    } catch (error) {
      if (mounted.current) Alert.alert("Não foi possível iniciar o chat", error instanceof Error ? error.message : "Falha ao iniciar conversa.");
    } finally {
      endMutation();
    }
  }

  async function send() {
    if (!selected || !draft.trim() || !beginMutation()) return;
    const text = draft.trim();
    setDraft("");
    try {
      const result = await sendChatMessage(sessionToken, deviceToken, selected.id, text);
      if (!mounted.current) return;
      setMessages((current) => {
        if (current.some((item) => item.id === result.message.id)) return current;
        const next = [...current, result.message];
        loadedMessageCount.current = next.length;
        return next;
      });
      await reloadConversations(false);
    } catch (error) {
      if (mounted.current) {
        setDraft(text);
        Alert.alert("Mensagem não enviada", error instanceof Error ? error.message : "Não foi possível enviar a mensagem.");
      }
    } finally {
      endMutation();
    }
  }

  async function toggleFavorite() {
    if (!selected || !beginMutation()) return;
    const nextValue = !selected.favorite;
    try {
      await setChatFavorite(sessionToken, deviceToken, selected.id, nextValue);
      if (!mounted.current) return;
      setSelected({ ...selected, favorite: nextValue });
      await reloadConversations(false);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível alterar o favorito.");
    } finally {
      endMutation();
    }
  }

  async function toggleMute() {
    if (!selected || !beginMutation()) return;
    const nextValue = !selected.muted;
    try {
      await setChatMuted(sessionToken, deviceToken, selected.id, nextValue);
      if (!mounted.current) return;
      setSelected({ ...selected, muted: nextValue });
      await reloadConversations(false);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível alterar as notificações.");
    } finally {
      endMutation();
    }
  }

  async function submitReport() {
    if (!selected || reportReason.trim().length < 5 || !beginMutation()) return;
    try {
      await reportChat(sessionToken, deviceToken, selected.id, reportReason.trim());
      if (!mounted.current) return;
      setReportOpen(false);
      setReportReason("");
      Alert.alert("Denúncia enviada", "A denúncia foi registrada de forma auditada. O chat não é aberto automaticamente para administração.");
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao denunciar", error instanceof Error ? error.message : "Não foi possível registrar a denúncia.");
    } finally {
      endMutation();
    }
  }

  useEffect(() => {
    mounted.current = true;
    reloadConversations(true).catch(() => {});
    const timer = setInterval(() => {
      if (!mounted.current || mutationLock.current || loadingOlderRef.current) return;
      reloadConversations(false).catch(() => {});
      const current = selected;
      if (current) reloadMessages(current, false, true).catch(() => {});
    }, 8_000);
    return () => {
      mounted.current = false;
      conversationVersion.current += 1;
      clearInterval(timer);
    };
  }, [sessionToken, deviceToken, selected?.id]);

  useEffect(() => {
    const q = search.trim();
    if (q.length < 2) {
      setProfiles([]);
      setSearching(false);
      return;
    }
    let cancelled = false;
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const result = await searchPublicProfiles(sessionToken, deviceToken, q, 15, 0);
        if (!cancelled && mounted.current) setProfiles(result.profiles);
      } catch {
        if (!cancelled && mounted.current) setProfiles([]);
      } finally {
        if (!cancelled && mounted.current) setSearching(false);
      }
    }, 450);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [search, sessionToken, deviceToken]);

  if (selected) {
    return (
      <View style={s.root}>
        <View style={s.chatHeader}>
          <Pressable style={s.backButton} onPress={() => {
            conversationVersion.current += 1;
            loadedMessageCount.current = 0;
            loadingOlderRef.current = false;
            setLoadingOlder(false);
            setSelected(null);
            setMessages([]);
            setHasOlderMessages(false);
          }}>
            <Text style={s.backText}>VOLTAR</Text>
          </Pressable>
          <View style={[s.avatar, selected.other.role === "DEV" && s.avatarDev]}>
            <Text style={s.avatarText}>{selected.other.publicName.slice(0, 1).toUpperCase()}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <View style={s.nameRow}>
              <Text style={s.chatName}>{selected.other.publicName}</Text>
              <Text style={[s.roleBadge, selected.other.role === "DEV" && s.roleBadgeDev]}>{selected.other.role}</Text>
            </View>
            <Text style={s.small}>{selected.other.statusText || "Conversa privada"}</Text>
          </View>
        </View>

        <View style={s.actionRow}>
          <Pressable disabled={busy} style={[s.action, selected.favorite && s.actionActive]} onPress={toggleFavorite}>
            <Text style={[s.actionText, selected.favorite && s.actionTextActive]}>{selected.favorite ? "FAVORITA" : "FAVORITAR"}</Text>
          </Pressable>
          <Pressable disabled={busy} style={[s.action, selected.muted && s.actionActive]} onPress={toggleMute}>
            <Text style={[s.actionText, selected.muted && s.actionTextActive]}>{selected.muted ? "MUDO" : "SILENCIAR"}</Text>
          </Pressable>
          <Pressable disabled={busy} style={[s.action, s.report]} onPress={() => setReportOpen(true)}>
            <Text style={[s.actionText, s.reportText]}>DENUNCIAR</Text>
          </Pressable>
        </View>

        <View style={s.retentionNote}>
          <Text style={s.retentionText}>
            Mensagens normais expiram em 24h. Se qualquer participante favoritar esta conversa, as mensagens são preservadas até que a conversa deixe de estar favorita.
          </Text>
        </View>

        {messagesLoading ? <ActivityIndicator style={{ marginVertical: 24 }} /> : (
          <>
            {hasOlderMessages ? (
              <Pressable style={[s.loadOlder, loadingOlder && s.disabled]} disabled={loadingOlder} onPress={() => { loadOlderMessages().catch(() => {}); }}>
                <Text style={s.loadOlderText}>{loadingOlder ? "CARREGANDO..." : "CARREGAR MENSAGENS MAIS ANTIGAS"}</Text>
              </Pressable>
            ) : messages.length > MESSAGE_PAGE_SIZE ? (
              <Text style={s.historyEnd}>Início do histórico disponível</Text>
            ) : null}

            {messages.length === 0 ? (
              <Text style={s.empty}>Nenhuma mensagem ainda. Envie a primeira.</Text>
            ) : messages.map((message) => (
              <View key={message.id} style={[s.messageRow, message.mine && s.messageRowMine]}>
                <View style={[s.bubble, message.mine && s.bubbleMine]}>
                  {!message.mine ? (
                    <View style={s.senderRow}>
                      <Text style={s.sender}>{message.sender.publicName}</Text>
                      <Text style={[s.messageRole, message.sender.role === "DEV" && s.messageRoleDev]}>{message.sender.role}</Text>
                    </View>
                  ) : null}
                  <Text style={s.messageText}>{message.text}</Text>
                  <Text style={s.messageMeta}>{dateText(message.createdAt)} • {expiryText(message.expiresAt)}</Text>
                </View>
              </View>
            ))}
          </>
        )}

        <View style={s.composer}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            multiline
            maxLength={2000}
            editable={!busy}
            style={s.messageInput}
            placeholder="Escreva uma mensagem..."
            placeholderTextColor="rgba(230,230,236,0.46)"
            textAlignVertical="top"
          />
          <Pressable style={[s.send, (!draft.trim() || busy) && s.disabled]} disabled={!draft.trim() || busy} onPress={send}>
            <Text style={s.sendText}>{busy ? "..." : "ENVIAR"}</Text>
          </Pressable>
        </View>

        <Modal visible={reportOpen} transparent animationType="fade" onRequestClose={() => { if (!busy) setReportOpen(false); }}>
          <KeyboardAvoidingView style={s.modalBackdrop} behavior={Platform.OS === "ios" ? "padding" : "height"}>
            <View style={s.modalBox}>
              <Text style={s.modalTitle}>Denunciar conversa</Text>
              <Text style={s.modalText}>Explique o motivo. A denúncia é registrada; o conteúdo privado não é automaticamente exibido para administração.</Text>
              <TextInput
                value={reportReason}
                onChangeText={setReportReason}
                maxLength={500}
                multiline
                editable={!busy}
                style={[s.messageInput, { minHeight: 110 }]}
                placeholder="Motivo da denúncia..."
                placeholderTextColor="rgba(230,230,236,0.46)"
                textAlignVertical="top"
              />
              <Pressable style={[s.modalPrimary, (busy || reportReason.trim().length < 5) && s.disabled]} disabled={busy || reportReason.trim().length < 5} onPress={submitReport}>
                <Text style={s.modalPrimaryText}>{busy ? "ENVIANDO..." : "ENVIAR DENÚNCIA"}</Text>
              </Pressable>
              <Pressable disabled={busy} style={s.modalSecondary} onPress={() => { setReportOpen(false); setReportReason(""); }}>
                <Text style={s.modalSecondaryText}>CANCELAR</Text>
              </Pressable>
            </View>
          </KeyboardAvoidingView>
        </Modal>
      </View>
    );
  }

  return (
    <View style={s.root}>
      <View style={s.listTitleRow}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>Conversas privadas</Text>
          <Text style={s.subtitle}>{unreadTotal > 0 ? `${unreadTotal} mensagem(ns) não lida(s)` : "Tudo em dia"}</Text>
        </View>
        <Pressable
          style={s.refresh}
          onPress={() => reloadConversations(true)}
          disabled={loading}
          accessibilityRole="button"
          accessibilityLabel="Atualizar conversas"
        >
          <Text style={s.refreshText}>ATUALIZAR</Text>
        </Pressable>
      </View>

      <TextInput
        value={search}
        onChangeText={setSearch}
        style={s.searchInput}
        placeholder="Buscar pseudônimo para conversar..."
        placeholderTextColor="rgba(230,230,236,0.48)"
        autoCapitalize="none"
        autoCorrect={false}
      />
      {searching ? <ActivityIndicator style={{ marginVertical: 8 }} /> : null}
      {profiles.length > 0 ? (
        <View style={s.searchResults}>
          {profiles.map((profile) => (
            <Pressable key={profile.profileId || profile.publicName} style={s.profileResult} disabled={busy} onPress={() => startWithProfile(profile)}>
              <View style={[s.avatarSmall, profile.role === "DEV" && s.avatarDev]}><Text style={s.avatarText}>{profile.publicName.slice(0, 1).toUpperCase()}</Text></View>
              <View style={{ flex: 1 }}>
                <View style={s.nameRow}>
                  <Text style={s.resultName}>{profile.publicName}</Text>
                  <Text style={[s.roleBadge, profile.role === "DEV" && s.roleBadgeDev]}>{profile.role}</Text>
                </View>
                <Text style={s.small}>{profile.statusText || profile.bio || "Abrir conversa"}</Text>
              </View>
              <ChevronIcon />
            </Pressable>
          ))}
        </View>
      ) : null}

      <View style={s.privacyCard}>
        <Text style={s.privacyTitle}>Privacidade</Text>
        <Text style={s.privacyText}>Enquanto a conta estiver ativa, não existe uma tela administrativa comum para abrir suas conversas privadas.</Text>
      </View>

      {loading ? <ActivityIndicator style={{ marginVertical: 26 }} /> : conversations.length === 0 ? (
        <Text style={s.empty}>Nenhuma conversa. Busque um pseudônimo acima para começar.</Text>
      ) : conversations.map((conversation) => (
        <Pressable key={conversation.id} style={[s.conversationCard, conversation.unreadCount > 0 && s.unreadCard]} onPress={() => openConversation(conversation)}>
          <View style={[s.avatar, conversation.other.role === "DEV" && s.avatarDev]}>
            <Text style={s.avatarText}>{conversation.other.publicName.slice(0, 1).toUpperCase()}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <View style={s.nameRow}>
              <Text style={s.chatName}>{conversation.other.publicName}</Text>
              <Text style={[s.roleBadge, conversation.other.role === "DEV" && s.roleBadgeDev]}>{conversation.other.role}</Text>
              {conversation.favorite ? <Text style={s.favorite}>FAV</Text> : null}
            </View>
            <Text numberOfLines={1} style={s.preview}>
              {conversation.latestMessage ? `${conversation.latestMessage.mine ? "Você: " : ""}${conversation.latestMessage.text}` : "Conversa iniciada"}
            </Text>
            <Text style={s.small}>{dateText(conversation.latestMessage?.createdAt || conversation.updatedAt)}</Text>
          </View>
          {conversation.unreadCount > 0 ? <View style={s.unreadBadge}><Text style={s.unreadText}>{conversation.unreadCount > 99 ? "99+" : conversation.unreadCount}</Text></View> : <ChevronIcon />}
        </Pressable>
      ))}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  listTitleRow: { flexDirection: "row", alignItems: "center", marginBottom: 10 },
  title: { color: "#FFF", fontSize: 20, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.58)", fontSize: 9, marginTop: 3 },
  refresh: { minHeight: 36, borderRadius: 8, borderWidth: 1, borderColor: "rgba(255,255,255,0.15)", backgroundColor: "rgba(0,0,0,0.12)", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  refreshText: { color: "rgba(245,245,248,0.72)", fontSize: 7, fontWeight: "900", letterSpacing: 0.3 },
  searchInput: { minHeight: 47, borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,255,255,0.18)", backgroundColor: "rgba(5,5,8,0.28)", color: "#FFF", paddingHorizontal: 13 },
  searchResults: { borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(5,5,8,0.78)", marginTop: 7, overflow: "hidden" },
  profileResult: { flexDirection: "row", alignItems: "center", gap: 10, padding: 11, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "rgba(255,255,255,0.12)" },
  avatarSmall: { width: 34, height: 34, borderRadius: 17, borderWidth: 1, borderColor: "rgba(255,255,255,0.30)", backgroundColor: "rgba(0,0,0,0.24)", alignItems: "center", justifyContent: "center" },
  resultName: { color: "#FFF", fontSize: 12, fontWeight: "900" },
  privacyCard: { borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(5,5,7,0.20)", padding: 11, marginTop: 10, marginBottom: 4 },
  privacyTitle: { color: "#FF8A92", fontSize: 9, fontWeight: "900" },
  privacyText: { color: "rgba(235,235,240,0.56)", fontSize: 8, lineHeight: 13, marginTop: 4 },
  conversationCard: { flexDirection: "row", alignItems: "center", gap: 11, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(3,3,5,0.07)", paddingHorizontal: 3, paddingVertical: 12, marginTop: 2 },
  unreadCard: { borderBottomColor: "rgba(255,38,56,0.42)", backgroundColor: "rgba(75,5,12,0.16)" },
  avatar: { width: 43, height: 43, borderRadius: 22, borderWidth: 1, borderColor: "rgba(255,255,255,0.32)", backgroundColor: "rgba(0,0,0,0.26)", alignItems: "center", justifyContent: "center" },
  avatarDev: { borderColor: "#D9464E", borderWidth: 2 },
  avatarText: { color: "#FFF", fontSize: 14, fontWeight: "900" },
  nameRow: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  chatName: { color: "#FFF", fontSize: 13, fontWeight: "900" },
  roleBadge: { color: "#FFFFFF", fontSize: 6, fontWeight: "900", backgroundColor: "rgba(91,32,38,0.68)", borderRadius: 4, paddingHorizontal: 5, paddingVertical: 2 },
  roleBadgeDev: { backgroundColor: "rgba(121,17,24,0.84)" },
  favorite: { color: "#FF8A92", fontSize: 6, fontWeight: "900", borderWidth: 1, borderColor: "rgba(255,38,56,0.34)", borderRadius: 4, paddingHorizontal: 4, paddingVertical: 1 },
  preview: { color: "rgba(235,235,240,0.62)", fontSize: 10, marginTop: 4 },
  small: { color: "rgba(225,225,232,0.46)", fontSize: 8, marginTop: 4 },
  chevronIcon: { width: 8, height: 8, borderRightWidth: 1.5, borderBottomWidth: 1.5, borderColor: "rgba(235,235,240,0.50)", transform: [{ rotate: "-45deg" }], marginRight: 4 },
  unreadBadge: { minWidth: 24, height: 24, borderRadius: 12, backgroundColor: "#FF2638", alignItems: "center", justifyContent: "center", paddingHorizontal: 5 },
  unreadText: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  empty: { color: "rgba(235,235,240,0.54)", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 24 },
  chatHeader: { flexDirection: "row", alignItems: "center", gap: 10, marginHorizontal: -12, paddingHorizontal: 14, paddingBottom: 10, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "rgba(255,255,255,0.14)" },
  backButton: { minHeight: 38, justifyContent: "center", paddingRight: 4 },
  backText: { color: "rgba(245,245,248,0.70)", fontSize: 8, fontWeight: "900" },
  actionRow: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 9 },
  action: { borderRadius: 8, borderWidth: 1, borderColor: "rgba(255,255,255,0.15)", backgroundColor: "rgba(0,0,0,0.10)", paddingHorizontal: 9, paddingVertical: 8 },
  actionActive: { borderColor: "rgba(255,38,56,0.48)", backgroundColor: "rgba(83,7,14,0.24)" },
  actionText: { color: "rgba(235,235,240,0.68)", fontSize: 7, fontWeight: "900" },
  actionTextActive: { color: "#FF8A92" },
  report: { borderColor: "rgba(255,80,90,0.30)" },
  reportText: { color: "#FF7A83" },
  retentionNote: { borderRadius: 9, borderWidth: 1, borderColor: "rgba(255,255,255,0.12)", backgroundColor: "rgba(0,0,0,0.14)", padding: 9, marginTop: 9, marginBottom: 4 },
  retentionText: { color: "rgba(235,235,240,0.48)", fontSize: 8, lineHeight: 13 },
  loadOlder: { minHeight: 37, borderRadius: 8, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(0,0,0,0.14)", alignItems: "center", justifyContent: "center", marginTop: 9, marginBottom: 3 },
  loadOlderText: { color: "rgba(245,245,248,0.68)", fontSize: 7, fontWeight: "900" },
  historyEnd: { color: "rgba(225,225,232,0.42)", fontSize: 8, textAlign: "center", marginTop: 10, marginBottom: 3 },
  messageRow: { alignItems: "flex-start", marginTop: 8 },
  messageRowMine: { alignItems: "flex-end" },
  bubble: { maxWidth: "84%", borderRadius: 13, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(3,3,6,0.26)", paddingHorizontal: 12, paddingVertical: 9 },
  bubbleMine: { backgroundColor: "rgba(85,7,14,0.30)", borderColor: "rgba(255,38,56,0.38)" },
  senderRow: { flexDirection: "row", alignItems: "center", gap: 5, marginBottom: 4 },
  sender: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  messageRole: { color: "#FFFFFF", fontSize: 5, fontWeight: "900", backgroundColor: "rgba(91,32,38,0.62)", borderRadius: 3, paddingHorizontal: 4, paddingVertical: 1 },
  messageRoleDev: { backgroundColor: "rgba(121,17,24,0.82)" },
  messageText: { color: "#EEEEF2", fontSize: 11, lineHeight: 17 },
  messageMeta: { color: "rgba(225,225,232,0.43)", fontSize: 7, marginTop: 5 },
  composer: { flexDirection: "row", alignItems: "flex-end", gap: 8, marginTop: 13 },
  messageInput: { flex: 1, minHeight: 48, maxHeight: 140, borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(5,5,8,0.28)", color: "#FFF", paddingHorizontal: 12, paddingVertical: 11 },
  send: { minWidth: 70, minHeight: 48, borderRadius: 11, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  sendText: { color: "#050505", fontSize: 8, fontWeight: "900" },
  disabled: { opacity: 0.42 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.74)", alignItems: "center", justifyContent: "center", padding: 18 },
  modalBox: { width: "100%", maxWidth: 520, borderRadius: 18, borderWidth: 1, borderColor: "rgba(255,255,255,0.18)", backgroundColor: "rgba(8,8,10,0.90)", padding: 17 },
  modalTitle: { color: "#FFF", fontSize: 18, fontWeight: "900" },
  modalText: { color: "rgba(235,235,240,0.58)", fontSize: 10, lineHeight: 16, marginTop: 7, marginBottom: 10 },
  modalPrimary: { minHeight: 48, borderRadius: 11, backgroundColor: "rgba(122,14,22,0.76)", borderWidth: 1, borderColor: "rgba(255,74,84,0.38)", alignItems: "center", justifyContent: "center", marginTop: 12 },
  modalPrimaryText: { color: "#FF9BA2", fontSize: 9, fontWeight: "900" },
  modalSecondary: { minHeight: 44, alignItems: "center", justifyContent: "center", marginTop: 5 },
  modalSecondaryText: { color: "rgba(235,235,240,0.58)", fontSize: 8, fontWeight: "900" }
});