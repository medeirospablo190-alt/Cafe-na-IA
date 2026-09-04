import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Clipboard from "expo-clipboard";
import {
  App1ApiError,
  type App1ManagedMenu,
  type App1MenuKey,
  type MenuKeyKind,
  configureApp1VipKey,
  createApp1MenuKey,
  listApp1ManagedMenus,
  listApp1MenuKeys,
  releaseApp1FreeKey,
  resetApp1MenuKeyDevice,
  setApp1MenuKeyState
} from "./api";

function errorText(error: unknown) {
  if (error instanceof App1ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return "Não foi possível concluir a operação.";
}

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function durationText(key: App1MenuKey) {
  if (key.kind === "FREE") return `${key.duration_value || 24}h por liberação`;
  if (key.duration_unit === "PERMANENT") return "Permanente";
  if (key.duration_unit === "MONTHS") return `${key.duration_value || 1} mês(es)`;
  return `${key.duration_value || 1} dia(s)`;
}

function stateText(key: App1MenuKey) {
  if (key.status === "SUSPENDED") return "SUSPENSA";
  if (key.status === "REVOKED") return "REVOGADA";
  if (key.access_state === "WAITING_ADMIN") return "AGUARDA ADM";
  if (key.access_state === "EXPIRED") return "EXPIRADA";
  if (key.access_state === "ACTIVE") return "EM USO";
  return "PRONTA";
}

export function KeysScreen({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [menus, setMenus] = useState<App1ManagedMenu[]>([]);
  const [selected, setSelected] = useState<App1ManagedMenu | null>(null);
  const [keys, setKeys] = useState<App1MenuKey[]>([]);
  const [loading, setLoading] = useState(true);
  const [keysLoading, setKeysLoading] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [kind, setKind] = useState<MenuKeyKind>("FREE");
  const [durationValue, setDurationValue] = useState("24");
  const [vipUnit, setVipUnit] = useState<"DAYS" | "MONTHS" | "PERMANENT">("DAYS");
  const [note, setNote] = useState("");
  const [revealed, setRevealed] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function loadMenus() {
    setLoading(true);
    try {
      const result = await listApp1ManagedMenus(sessionToken, deviceToken);
      setMenus(result.menus);
      if (selected) {
        const updated = result.menus.find((item) => item.id === selected.id) || null;
        setSelected(updated);
      }
    } catch (error) {
      Alert.alert("Menus indisponíveis", errorText(error));
    } finally {
      setLoading(false);
    }
  }

  async function loadKeys(menu = selected) {
    if (!menu) return;
    setKeysLoading(true);
    try {
      const result = await listApp1MenuKeys(sessionToken, deviceToken, menu.id);
      setKeys(result.keys);
    } catch (error) {
      setKeys([]);
      Alert.alert("Chaves indisponíveis", errorText(error));
    } finally {
      setKeysLoading(false);
    }
  }

  useEffect(() => {
    loadMenus().catch(() => {});
  }, [sessionToken, deviceToken]);

  async function openMenu(menu: App1ManagedMenu) {
    setSelected(menu);
    await loadKeys(menu);
  }

  function openCreate() {
    setKind("FREE");
    setDurationValue("24");
    setVipUnit("DAYS");
    setNote("");
    setCreateOpen(true);
  }

  async function createKey() {
    if (!selected || busy) return;
    const numeric = Math.max(1, Math.floor(Number(durationValue || 1)));
    if (kind === "FREE" && numeric > 24) {
      Alert.alert("Limite FREE", "A chave FREE pode liberar no máximo 24 horas por ciclo.");
      return;
    }
    setBusy(true);
    try {
      const result = await createApp1MenuKey(sessionToken, deviceToken, selected.id, {
        kind,
        durationValue: vipUnit === "PERMANENT" && kind === "VIP" ? undefined : numeric,
        durationUnit: kind === "VIP" ? vipUnit : undefined,
        note: note.trim() || undefined
      });
      setRevealed(result.key.value);
      setCreateOpen(false);
      await Promise.all([loadKeys(selected), loadMenus()]);
    } catch (error) {
      Alert.alert("Não foi possível gerar", errorText(error));
    } finally {
      setBusy(false);
    }
  }

  async function releaseFree(key: App1MenuKey) {
    setBusy(true);
    try {
      await releaseApp1FreeKey(sessionToken, deviceToken, key.id, Math.min(24, Math.max(1, key.duration_value || 24)));
      await loadKeys();
      Alert.alert("FREE liberada", "Um novo período será iniciado quando a chave for usada novamente no aparelho vinculado.");
    } catch (error) {
      Alert.alert("Falha ao liberar", errorText(error));
    } finally {
      setBusy(false);
    }
  }

  async function renewVip(key: App1MenuKey) {
    setBusy(true);
    try {
      const unit = key.duration_unit === "MONTHS" || key.duration_unit === "PERMANENT" ? key.duration_unit : "DAYS";
      await configureApp1VipKey(sessionToken, deviceToken, key.id, unit, key.duration_value || 30);
      await loadKeys();
      Alert.alert("VIP renovada", "A validade configurada começará no próximo uso da chave.");
    } catch (error) {
      Alert.alert("Falha ao renovar", errorText(error));
    } finally {
      setBusy(false);
    }
  }

  async function resetDevice(key: App1MenuKey) {
    Alert.alert(
      "Trocar aparelho",
      "As sessões atuais desta chave serão encerradas. O próximo aparelho que usar a chave ficará vinculado a ela.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Desvincular",
          style: "destructive",
          onPress: async () => {
            setBusy(true);
            try {
              await resetApp1MenuKeyDevice(sessionToken, deviceToken, key.id);
              await loadKeys();
            } catch (error) {
              Alert.alert("Falha", errorText(error));
            } finally {
              setBusy(false);
            }
          }
        }
      ]
    );
  }

  async function toggleKey(key: App1MenuKey) {
    const action = key.status === "ACTIVE" ? "suspend" : "restore";
    setBusy(true);
    try {
      await setApp1MenuKeyState(sessionToken, deviceToken, key.id, action);
      await loadKeys();
    } catch (error) {
      Alert.alert("Falha", errorText(error));
    } finally {
      setBusy(false);
    }
  }

  function revokeKey(key: App1MenuKey) {
    Alert.alert("Revogar chave", "Esta ação encerra as sessões da chave e não pode ser desfeita.", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Revogar",
        style: "destructive",
        onPress: async () => {
          setBusy(true);
          try {
            await setApp1MenuKeyState(sessionToken, deviceToken, key.id, "revoke");
            await loadKeys();
          } catch (error) {
            Alert.alert("Falha", errorText(error));
          } finally {
            setBusy(false);
          }
        }
      }
    ]);
  }

  const usable = useMemo(() => keys.filter((item) => item.usable && item.status === "ACTIVE").length, [keys]);

  if (!selected) {
    return (
      <View>
        <View style={s.infoCard}>
          <Text style={s.infoTitle}>FREE e VIP</Text>
          <Text style={s.infoText}>As chaves dos menus são administradas somente no App 1. FREE usa ciclos de até 24h; VIP pode usar dias, meses ou permanente.</Text>
        </View>
        {loading ? <ActivityIndicator style={{ marginTop: 24 }} /> : menus.length === 0 ? (
          <Text style={s.empty}>Nenhum menu cadastrado no servidor.</Text>
        ) : menus.map((menu) => (
          <Pressable key={menu.id} style={s.menuCard} onPress={() => openMenu(menu)}>
            <View style={{ flex: 1 }}>
              <Text style={s.title}>{menu.name}</Text>
              <Text style={s.meta}>{menu.public_id}</Text>
              <Text style={s.meta}>{menu.key_count} chave(s)</Text>
            </View>
            <Text style={menu.status === "ACTIVE" ? s.ok : s.bad}>{menu.status === "ACTIVE" ? "ATIVO" : "SUSPENSO"}</Text>
          </Pressable>
        ))}
      </View>
    );
  }

  return (
    <View>
      <View style={s.headerRow}>
        <Pressable style={s.back} onPress={() => { setSelected(null); setKeys([]); }}><Text style={s.backText}>‹ MENUS</Text></Pressable>
        <Pressable style={s.add} onPress={openCreate}><Text style={s.addText}>＋ CHAVE</Text></Pressable>
      </View>

      <View style={s.infoCard}>
        <Text style={s.infoTitle}>{selected.name}</Text>
        <Text style={s.infoText}>{selected.public_id} • {usable} utilizável(is) • {keys.length} total</Text>
      </View>

      {keysLoading ? <ActivityIndicator style={{ marginTop: 24 }} /> : keys.length === 0 ? (
        <Text style={s.empty}>Nenhuma chave cadastrada neste menu.</Text>
      ) : keys.map((key) => (
        <View key={key.id} style={s.keyCard}>
          <View style={s.keyTop}>
            <View style={{ flex: 1 }}>
              <View style={s.badgeRow}>
                <Text style={[s.kind, key.kind === "VIP" && s.vip]}>{key.kind}</Text>
                <Text style={key.usable ? s.ok : s.bad}>{stateText(key)}</Text>
              </View>
              <Text style={s.title}>{key.key_hint}</Text>
              <Text style={s.meta}>{durationText(key)}{key.note ? ` • ${key.note}` : ""}</Text>
              <Text style={s.meta}>Aparelho: {key.bound_device ? key.bound_device_hint || "vinculado" : "ainda não vinculado"}</Text>
              <Text style={s.meta}>Início: {dateText(key.access_started_at)}</Text>
              <Text style={s.meta}>Até: {key.duration_unit === "PERMANENT" && key.access_state === "ACTIVE" ? "PERMANENTE" : dateText(key.access_until)}</Text>
            </View>
          </View>

          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.actions}>
            {key.kind === "FREE" && key.access_state === "WAITING_ADMIN" && key.status !== "REVOKED" ? (
              <Action label="LIBERAR FREE" onPress={() => releaseFree(key)} />
            ) : null}
            {key.kind === "VIP" && key.status !== "REVOKED" ? (
              <Action label={key.access_state === "EXPIRED" ? "RENOVAR VIP" : "REINICIAR VIP"} onPress={() => renewVip(key)} />
            ) : null}
            {key.bound_device && key.status !== "REVOKED" ? <Action label="TROCAR CELULAR" onPress={() => resetDevice(key)} /> : null}
            {key.status !== "REVOKED" ? <Action label={key.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"} onPress={() => toggleKey(key)} /> : null}
            {key.status !== "REVOKED" ? <Action label="REVOGAR" danger onPress={() => revokeKey(key)} /> : null}
          </ScrollView>
        </View>
      ))}

      <Modal visible={createOpen} transparent animationType="fade" onRequestClose={() => setCreateOpen(false)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <Text style={s.modalTitle}>Gerar chave</Text>
            <View style={s.choiceRow}>
              <Choice label="FREE" active={kind === "FREE"} onPress={() => { setKind("FREE"); setDurationValue("24"); }} />
              <Choice label="VIP" active={kind === "VIP"} onPress={() => { setKind("VIP"); setDurationValue("30"); setVipUnit("DAYS"); }} />
            </View>

            {kind === "FREE" ? (
              <>
                <Text style={s.label}>HORAS DE ACESSO • MÁXIMO 24H</Text>
                <TextInput value={durationValue} onChangeText={setDurationValue} keyboardType="number-pad" style={s.input} placeholder="24" placeholderTextColor="#666" />
                <Text style={s.help}>Depois do período, a chave entra em AGUARDA ADM. Somente um ADM/DEV do App 1 pode liberar outro ciclo.</Text>
              </>
            ) : (
              <>
                <Text style={s.label}>VALIDADE VIP</Text>
                <View style={s.choiceRow}>
                  <Choice label="DIAS" active={vipUnit === "DAYS"} onPress={() => setVipUnit("DAYS")} />
                  <Choice label="MESES" active={vipUnit === "MONTHS"} onPress={() => setVipUnit("MONTHS")} />
                  <Choice label="PERMANENTE" active={vipUnit === "PERMANENT"} onPress={() => setVipUnit("PERMANENT")} />
                </View>
                {vipUnit !== "PERMANENT" ? <TextInput value={durationValue} onChangeText={setDurationValue} keyboardType="number-pad" style={s.input} placeholder="30" placeholderTextColor="#666" /> : null}
              </>
            )}

            <TextInput value={note} onChangeText={setNote} style={s.input} placeholder="Observação opcional" placeholderTextColor="#666" />
            <Pressable style={[s.primary, busy && { opacity: 0.5 }]} disabled={busy} onPress={createKey}><Text style={s.primaryText}>{busy ? "GERANDO..." : "GERAR CHAVE"}</Text></Pressable>
            <Pressable style={s.secondary} onPress={() => setCreateOpen(false)}><Text style={s.secondaryText}>CANCELAR</Text></Pressable>
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(revealed)} transparent animationType="fade" onRequestClose={() => setRevealed(null)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <Text style={s.modalTitle}>Chave criada</Text>
            <Text style={s.help}>Esta é a única exibição do valor completo. Copie antes de fechar.</Text>
            <Text selectable style={s.secret}>{revealed}</Text>
            <Pressable style={s.primary} onPress={async () => { if (revealed) await Clipboard.setStringAsync(revealed); }}><Text style={s.primaryText}>COPIAR CHAVE</Text></Pressable>
            <Pressable style={s.secondary} onPress={() => setRevealed(null)}><Text style={s.secondaryText}>FECHAR</Text></Pressable>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function Action({ label, onPress, danger = false }: { label: string; onPress: () => void; danger?: boolean }) {
  return <Pressable style={[s.action, danger && s.actionDanger]} onPress={onPress}><Text style={[s.actionText, danger && s.dangerText]}>{label}</Text></Pressable>;
}

function Choice({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return <Pressable style={[s.choice, active && s.choiceActive]} onPress={onPress}><Text style={[s.choiceText, active && s.choiceTextActive]}>{label}</Text></Pressable>;
}

const s = StyleSheet.create({
  infoCard: { borderRadius: 16, borderWidth: 1, borderColor: "#2A2A30", backgroundColor: "#0A0A0D", padding: 15, marginBottom: 12 },
  infoTitle: { color: "#FFF", fontSize: 17, fontWeight: "900" },
  infoText: { color: "#8D8D94", fontSize: 11, lineHeight: 17, marginTop: 6 },
  empty: { color: "#6F6F76", fontSize: 12, textAlign: "center", marginTop: 28 },
  menuCard: { flexDirection: "row", gap: 12, alignItems: "center", borderRadius: 16, borderWidth: 1, borderColor: "#242429", backgroundColor: "#09090B", padding: 15, marginBottom: 9 },
  keyCard: { borderRadius: 16, borderWidth: 1, borderColor: "#242429", backgroundColor: "#09090B", padding: 14, marginBottom: 10 },
  keyTop: { flexDirection: "row", gap: 10 },
  badgeRow: { flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 6 },
  kind: { color: "#65D97F", fontSize: 9, fontWeight: "900" },
  vip: { color: "#D49CFF" },
  ok: { color: "#65D97F", fontSize: 9, fontWeight: "900" },
  bad: { color: "#FF666C", fontSize: 9, fontWeight: "900" },
  title: { color: "#FFF", fontSize: 14, fontWeight: "900" },
  meta: { color: "#73737A", fontSize: 10, lineHeight: 16, marginTop: 3 },
  headerRow: { flexDirection: "row", justifyContent: "space-between", gap: 10, marginBottom: 10 },
  back: { paddingVertical: 8, paddingHorizontal: 10 },
  backText: { color: "#B4B4BA", fontSize: 10, fontWeight: "900" },
  add: { borderRadius: 10, borderWidth: 1, borderColor: "#393940", paddingHorizontal: 12, justifyContent: "center" },
  addText: { color: "#FFF", fontSize: 10, fontWeight: "900" },
  actions: { flexDirection: "row", gap: 7, marginTop: 12 },
  action: { borderRadius: 9, borderWidth: 1, borderColor: "#34343A", paddingHorizontal: 10, paddingVertical: 8 },
  actionDanger: { borderColor: "#542126", backgroundColor: "#130708" },
  actionText: { color: "#C5C5CA", fontSize: 8, fontWeight: "900" },
  dangerText: { color: "#FF676E" },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.82)", alignItems: "center", justifyContent: "center", padding: 18 },
  modalBox: { width: "100%", maxWidth: 520, borderRadius: 20, borderWidth: 1, borderColor: "#303036", backgroundColor: "#09090C", padding: 18 },
  modalTitle: { color: "#FFF", fontSize: 21, fontWeight: "900", marginBottom: 12 },
  label: { color: "#77777E", fontSize: 9, fontWeight: "900", letterSpacing: 1.1, marginTop: 12 },
  help: { color: "#85858C", fontSize: 10, lineHeight: 16, marginTop: 8 },
  input: { minHeight: 48, borderRadius: 12, borderWidth: 1, borderColor: "#2C2C32", backgroundColor: "#111114", color: "#FFF", paddingHorizontal: 12, marginTop: 10 },
  choiceRow: { flexDirection: "row", gap: 8, flexWrap: "wrap" },
  choice: { borderRadius: 10, borderWidth: 1, borderColor: "#303037", paddingHorizontal: 12, paddingVertical: 9 },
  choiceActive: { borderColor: "#FFF", backgroundColor: "#FFF" },
  choiceText: { color: "#8A8A91", fontSize: 9, fontWeight: "900" },
  choiceTextActive: { color: "#050505" },
  primary: { minHeight: 49, borderRadius: 12, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 14 },
  primaryText: { color: "#050505", fontSize: 10, fontWeight: "900" },
  secondary: { minHeight: 45, alignItems: "center", justifyContent: "center", marginTop: 6 },
  secondaryText: { color: "#88888F", fontSize: 9, fontWeight: "900" },
  secret: { color: "#FFF", backgroundColor: "#111116", borderRadius: 12, borderWidth: 1, borderColor: "#34343A", padding: 13, fontSize: 12, lineHeight: 18, marginTop: 10 }
});
