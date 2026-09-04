import { useEffect, useMemo, useRef, useState } from "react";
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
import * as Clipboard from "expo-clipboard";
import {
  type App1MenuKey,
  claimApp1MenuKey,
  listApp1MenuKeys,
  removeApp1MenuKey,
  revealApp1MenuKey
} from "./keys-api";

type Filter = "ALL" | "FREE" | "VIP" | "SUSPENDED";

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function statusLabel(item: App1MenuKey) {
  if (item.status === "ACTIVE") return "ATIVA";
  if (item.status === "SUSPENDED") return "SUSPENSA";
  if (item.status === "MENU_SUSPENDED") return "MENU SUSPENSO";
  if (item.status === "EXPIRED") return "EXPIRADA";
  return "REVOGADA";
}

export function KeysScreen({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [items, setItems] = useState<App1MenuKey[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>("ALL");
  const [claimOpen, setClaimOpen] = useState(false);
  const [menuId, setMenuId] = useState("");
  const [keyValue, setKeyValue] = useState("");
  const [busy, setBusy] = useState(false);
  const mounted = useRef(true);
  const loadVersion = useRef(0);
  const mutationLock = useRef(false);

  useEffect(() => {
    mounted.current = true;
    load().catch(() => {});
    return () => {
      mounted.current = false;
      loadVersion.current += 1;
    };
  }, [sessionToken, deviceToken]);

  async function load(preserveMessage = false) {
    const version = ++loadVersion.current;
    setLoading(true);
    if (!preserveMessage) setMessage(null);
    try {
      const result = await listApp1MenuKeys(sessionToken, deviceToken);
      if (!mounted.current || version !== loadVersion.current) return;
      setItems(result.keys);
    } catch (error) {
      if (!mounted.current || version !== loadVersion.current) return;
      setMessage(error instanceof Error ? error.message : "Não foi possível carregar suas chaves.");
    } finally {
      if (mounted.current && version === loadVersion.current) setLoading(false);
    }
  }

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((item) => {
      if (filter === "FREE" && item.kind !== "FREE") return false;
      if (filter === "VIP" && item.kind !== "VIP") return false;
      if (filter === "SUSPENDED" && item.status === "ACTIVE") return false;
      if (!q) return true;
      return item.menu.name.toLowerCase().includes(q) ||
        item.menu.publicId.toLowerCase().includes(q) ||
        item.keyHint.toLowerCase().includes(q) ||
        String(item.note || "").toLowerCase().includes(q);
    });
  }, [items, query, filter]);

  const freeCount = items.filter((item) => item.kind === "FREE").length;
  const vipCount = items.filter((item) => item.kind === "VIP").length;
  const usableCount = items.filter((item) => item.usable).length;

  async function claim() {
    if (!menuId.trim() || !keyValue.trim() || mutationLock.current) return;
    mutationLock.current = true;
    setBusy(true);
    setMessage(null);
    try {
      const result = await claimApp1MenuKey(sessionToken, deviceToken, {
        menuId: menuId.trim(),
        key: keyValue.trim()
      });
      setMenuId("");
      setKeyValue("");
      setClaimOpen(false);
      setMessage(result.created ? "Chave adicionada à sua conta." : "Essa chave já estava salva e foi confirmada novamente.");
      await load(true);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível adicionar a chave.");
    } finally {
      mutationLock.current = false;
      setBusy(false);
    }
  }

  async function copyKey(item: App1MenuKey) {
    if (!item.usable) {
      setMessage("Esta chave está inativa. Ela continuará visível para consulta, mas não pode ser copiada enquanto não voltar a ficar ativa.");
      return;
    }
    if (mutationLock.current) return;
    mutationLock.current = true;
    setBusy(true);
    setMessage(null);
    try {
      const result = await revealApp1MenuKey(sessionToken, deviceToken, item.bindingId);
      await Clipboard.setStringAsync(result.key);
      setMessage(`Chave ${item.kind} de ${item.menu.name} copiada.`);
      await load(true);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível copiar a chave.");
    } finally {
      mutationLock.current = false;
      setBusy(false);
    }
  }

  async function copyLink(item: App1MenuKey) {
    await Clipboard.setStringAsync(item.menu.accessUrl);
    setMessage(`Link de ${item.menu.name} copiado.`);
  }

  function confirmRemove(item: App1MenuKey) {
    Alert.alert(
      "Remover chave do App 1",
      `Remover a chave ${item.kind} de ${item.menu.name} desta conta? Isso não revoga a chave no menu.`,
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Remover", style: "destructive", onPress: () => remove(item) }
      ]
    );
  }

  async function remove(item: App1MenuKey) {
    if (mutationLock.current) return;
    mutationLock.current = true;
    setBusy(true);
    setMessage(null);
    try {
      await removeApp1MenuKey(sessionToken, deviceToken, item.bindingId);
      setItems((current) => current.filter((entry) => entry.bindingId !== item.bindingId));
      setMessage("Chave removida apenas da sua conta do App 1.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível remover a chave.");
    } finally {
      mutationLock.current = false;
      setBusy(false);
    }
  }

  return (
    <View style={styles.wrap}>
      <View style={styles.summaryRow}>
        <Summary label="ATIVAS" value={usableCount} />
        <Summary label="FREE" value={freeCount} />
        <Summary label="VIP" value={vipCount} />
      </View>

      <View style={styles.toolbar}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Buscar menu ou chave..."
          placeholderTextColor="#5D5D63"
          style={styles.search}
          autoCapitalize="none"
          autoCorrect={false}
        />
        <Pressable style={styles.addButton} onPress={() => setClaimOpen(true)} disabled={busy}>
          <Text style={styles.addButtonText}>+ ADICIONAR</Text>
        </Pressable>
      </View>

      <View style={styles.filters}>
        {(["ALL", "FREE", "VIP", "SUSPENDED"] as Filter[]).map((value) => (
          <Pressable
            key={value}
            style={[styles.filter, filter === value && styles.filterActive]}
            onPress={() => setFilter(value)}
          >
            <Text style={[styles.filterText, filter === value && styles.filterTextActive]}>
              {value === "ALL" ? "TODAS" : value === "SUSPENDED" ? "INATIVAS" : value}
            </Text>
          </Pressable>
        ))}
      </View>

      {message ? <Text style={styles.message}>{message}</Text> : null}

      {loading ? (
        <View style={styles.loadingRow}>
          <ActivityIndicator size="small" />
          <Text style={styles.muted}>Atualizando chaves...</Text>
        </View>
      ) : visible.length === 0 ? (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>Nenhuma chave encontrada</Text>
          <Text style={styles.muted}>
            Toque em ADICIONAR e informe o ID/link do menu junto com uma chave FREE ou VIP válida que foi entregue a você.
          </Text>
        </View>
      ) : (
        visible.map((item) => (
          <View key={item.bindingId} style={[styles.card, item.kind === "VIP" && styles.vipCard]}>
            <View style={styles.cardHeader}>
              <View style={styles.cardTitleWrap}>
                <Text style={styles.menuName}>{item.menu.name}</Text>
                <Text style={styles.publicId}>{item.menu.publicId}</Text>
              </View>
              <View style={[styles.kindBadge, item.kind === "VIP" && styles.vipBadge]}>
                <Text style={styles.kindText}>{item.kind}</Text>
              </View>
            </View>

            <View style={styles.stateRow}>
              <Text style={[styles.state, item.usable ? styles.stateActive : styles.stateInactive]}>
                {statusLabel(item)}
              </Text>
              <Text style={styles.hint}>{item.keyHint}</Text>
            </View>

            <View style={styles.metaGrid}>
              <Meta label="VALIDADE" value={item.kind === "VIP" ? "Permanente" : formatDate(item.expiresAt)} />
              <Meta label="USOS" value={String(item.useCount)} />
              <Meta label="ÚLTIMO USO" value={formatDate(item.lastUsedAt)} />
              <Meta label="ADICIONADA" value={formatDate(item.addedAt)} />
            </View>

            {item.note ? <Text style={styles.note}>{item.note}</Text> : null}

            <View style={styles.actions}>
              <Pressable
                style={[styles.actionButton, (!item.usable || busy) && styles.disabled]}
                onPress={() => copyKey(item)}
                disabled={busy || !item.usable}
              >
                <Text style={styles.actionText}>COPIAR CHAVE</Text>
              </Pressable>
              <Pressable style={styles.actionButton} onPress={() => copyLink(item)} disabled={busy}>
                <Text style={styles.actionText}>COPIAR LINK</Text>
              </Pressable>
              <Pressable style={styles.removeButton} onPress={() => confirmRemove(item)} disabled={busy}>
                <Text style={styles.removeText}>REMOVER</Text>
              </Pressable>
            </View>
          </View>
        ))
      )}

      <Modal visible={claimOpen} transparent animationType="fade" onRequestClose={() => !busy && setClaimOpen(false)}>
        <KeyboardAvoidingView style={styles.modalBackdrop} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <View style={styles.modalCard}>
            <Text style={styles.modalEyebrow}>MINHAS CHAVES</Text>
            <Text style={styles.modalTitle}>Adicionar FREE/VIP</Text>
            <Text style={styles.muted}>
              A chave é validada pelo servidor e fica vinculada somente à sua conta. Ela não é exibida nas listagens do aplicativo.
            </Text>
            <TextInput
              value={menuId}
              onChangeText={setMenuId}
              placeholder="ID do menu ou link /l/menu_..."
              placeholderTextColor="#5D5D63"
              style={styles.input}
              autoCapitalize="none"
              autoCorrect={false}
            />
            <TextInput
              value={keyValue}
              onChangeText={setKeyValue}
              placeholder="Chave FREE-... ou VIP-..."
              placeholderTextColor="#5D5D63"
              style={styles.input}
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
            />
            <View style={styles.modalActions}>
              <Pressable style={styles.cancelButton} onPress={() => setClaimOpen(false)} disabled={busy}>
                <Text style={styles.cancelText}>CANCELAR</Text>
              </Pressable>
              <Pressable
                style={[styles.confirmButton, (!menuId.trim() || !keyValue.trim() || busy) && styles.disabled]}
                onPress={claim}
                disabled={!menuId.trim() || !keyValue.trim() || busy}
              >
                <Text style={styles.confirmText}>{busy ? "VALIDANDO..." : "ADICIONAR"}</Text>
              </Pressable>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

function Summary({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.summary}>
      <Text style={styles.summaryValue}>{value}</Text>
      <Text style={styles.summaryLabel}>{label}</Text>
    </View>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.meta}>
      <Text style={styles.metaLabel}>{label}</Text>
      <Text style={styles.metaValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 10 },
  summaryRow: { flexDirection: "row", gap: 8 },
  summary: { flex: 1, borderRadius: 13, borderWidth: 1, borderColor: "#242429", backgroundColor: "#09090B", padding: 11 },
  summaryValue: { color: "#FFFFFF", fontWeight: "900", fontSize: 18 },
  summaryLabel: { color: "#6C6C73", fontWeight: "900", fontSize: 8, marginTop: 3, letterSpacing: 0.7 },
  toolbar: { flexDirection: "row", gap: 8, alignItems: "center" },
  search: { flex: 1, minHeight: 45, borderRadius: 12, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#0D0D10", color: "#FFFFFF", paddingHorizontal: 12, fontSize: 13 },
  addButton: { minHeight: 45, borderRadius: 12, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 13 },
  addButtonText: { color: "#050505", fontSize: 9, fontWeight: "900" },
  filters: { flexDirection: "row", flexWrap: "wrap", gap: 7 },
  filter: { borderRadius: 10, borderWidth: 1, borderColor: "#29292E", paddingHorizontal: 10, paddingVertical: 8, backgroundColor: "#09090B" },
  filterActive: { backgroundColor: "#FFFFFF", borderColor: "#FFFFFF" },
  filterText: { color: "#74747B", fontSize: 8, fontWeight: "900" },
  filterTextActive: { color: "#050505" },
  message: { color: "#D5D5DA", backgroundColor: "#0D0D10", borderWidth: 1, borderColor: "#29292E", borderRadius: 12, padding: 11, fontSize: 11, lineHeight: 16 },
  loadingRow: { flexDirection: "row", alignItems: "center", gap: 9, paddingVertical: 16 },
  muted: { color: "#7E7E85", fontSize: 11, lineHeight: 17 },
  emptyCard: { borderRadius: 16, borderWidth: 1, borderColor: "#25252A", backgroundColor: "#09090B", padding: 16 },
  emptyTitle: { color: "#FFFFFF", fontWeight: "900", fontSize: 14, marginBottom: 6 },
  card: { borderRadius: 16, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#09090B", padding: 14 },
  vipCard: { borderColor: "#5A5126" },
  cardHeader: { flexDirection: "row", alignItems: "flex-start", gap: 9 },
  cardTitleWrap: { flex: 1 },
  menuName: { color: "#FFFFFF", fontSize: 15, fontWeight: "900" },
  publicId: { color: "#66666D", fontSize: 9, marginTop: 3 },
  kindBadge: { borderRadius: 8, borderWidth: 1, borderColor: "#303037", backgroundColor: "#121216", paddingHorizontal: 8, paddingVertical: 5 },
  vipBadge: { borderColor: "#74672B", backgroundColor: "#1B1809" },
  kindText: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  stateRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 10, marginTop: 11 },
  state: { fontSize: 9, fontWeight: "900", letterSpacing: 0.5 },
  stateActive: { color: "#63D97C" },
  stateInactive: { color: "#FF646B" },
  hint: { color: "#8A8A91", fontSize: 9, flexShrink: 1, textAlign: "right" },
  metaGrid: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 11 },
  meta: { width: "47%", flexGrow: 1, borderRadius: 10, backgroundColor: "#0F0F12", padding: 9 },
  metaLabel: { color: "#5F5F66", fontSize: 7, fontWeight: "900", letterSpacing: 0.5 },
  metaValue: { color: "#C9C9CF", fontSize: 10, marginTop: 4 },
  note: { color: "#8F8F96", fontSize: 10, lineHeight: 15, marginTop: 10 },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 12 },
  actionButton: { borderRadius: 10, borderWidth: 1, borderColor: "#34343A", paddingHorizontal: 10, paddingVertical: 9, backgroundColor: "#111114" },
  actionText: { color: "#D8D8DD", fontSize: 8, fontWeight: "900" },
  removeButton: { borderRadius: 10, borderWidth: 1, borderColor: "#4A2024", paddingHorizontal: 10, paddingVertical: 9, backgroundColor: "#14090A" },
  removeText: { color: "#FF666C", fontSize: 8, fontWeight: "900" },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.78)", justifyContent: "center", padding: 18 },
  modalCard: { borderRadius: 20, borderWidth: 1, borderColor: "#303036", backgroundColor: "#0A0A0C", padding: 18 },
  modalEyebrow: { color: "#77777E", fontSize: 8, fontWeight: "900", letterSpacing: 1.4 },
  modalTitle: { color: "#FFFFFF", fontSize: 22, fontWeight: "900", marginTop: 6, marginBottom: 7 },
  input: { minHeight: 50, borderRadius: 13, borderWidth: 1, borderColor: "#2B2B30", backgroundColor: "#101013", color: "#FFFFFF", paddingHorizontal: 13, fontSize: 13, marginTop: 11 },
  modalActions: { flexDirection: "row", gap: 8, marginTop: 14 },
  cancelButton: { flex: 1, minHeight: 46, borderRadius: 12, borderWidth: 1, borderColor: "#303036", alignItems: "center", justifyContent: "center" },
  cancelText: { color: "#A0A0A7", fontSize: 9, fontWeight: "900" },
  confirmButton: { flex: 1, minHeight: 46, borderRadius: 12, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center" },
  confirmText: { color: "#050505", fontSize: 9, fontWeight: "900" },
  disabled: { opacity: 0.4 }
});
