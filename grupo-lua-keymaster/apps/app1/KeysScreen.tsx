import { useEffect, useMemo, useRef, useState } from "react";
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
import { revealApp1MenuKey, type RevealableMenuKey } from "./keyRevealApi";
import { buildMenuLoader } from "./menuLoader";

type VipUnit = "DAYS" | "MONTHS" | "PERMANENT";

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

function positiveInteger(value: string) {
  const parsed = Number(value.trim());
  if (!Number.isFinite(parsed)) return null;
  const numeric = Math.floor(parsed);
  return numeric >= 1 ? numeric : null;
}

function canRevealKey(key: App1MenuKey) {
  return Boolean((key as RevealableMenuKey).can_reveal) && key.status !== "REVOKED";
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
  const [vipUnit, setVipUnit] = useState<VipUnit>("DAYS");
  const [note, setNote] = useState("");
  const [revealed, setRevealed] = useState<string | null>(null);
  const [revealedTitle, setRevealedTitle] = useState("Chave");
  const [renewTarget, setRenewTarget] = useState<App1MenuKey | null>(null);
  const [renewDurationValue, setRenewDurationValue] = useState("24");
  const [renewVipUnit, setRenewVipUnit] = useState<VipUnit>("DAYS");
  const [busy, setBusy] = useState(false);
  const actionLock = useRef(false);

  async function runLocked(action: () => Promise<void>, errorTitle: string) {
    if (actionLock.current) return;
    actionLock.current = true;
    setBusy(true);
    try {
      await action();
    } catch (error) {
      Alert.alert(errorTitle, errorText(error));
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }

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
    if (actionLock.current) return;
    setKind("FREE");
    setDurationValue("24");
    setVipUnit("DAYS");
    setNote("");
    setCreateOpen(true);
  }

  async function copySelectedLoader() {
    if (!selected) return;
    const loader = buildMenuLoader(selected.public_id);
    if (!loader) {
      Alert.alert("ID inválido", "O ID público deste menu não está no formato esperado para gerar o loadstring.");
      return;
    }
    await Clipboard.setStringAsync(loader);
    Alert.alert("Loadstring copiado", `O loader de ${selected.name} foi copiado.`);
  }

  async function createKey() {
    if (!selected || actionLock.current) return;
    const numeric = positiveInteger(durationValue);
    if (!(kind === "VIP" && vipUnit === "PERMANENT") && numeric === null) {
      Alert.alert("Validade inválida", "Digite um número inteiro maior que zero.");
      return;
    }
    if (kind === "FREE" && (numeric || 0) > 24) {
      Alert.alert("Limite FREE", "A chave FREE pode liberar no máximo 24 horas por ciclo.");
      return;
    }

    await runLocked(async () => {
      const result = await createApp1MenuKey(sessionToken, deviceToken, selected.id, {
        kind,
        durationValue: vipUnit === "PERMANENT" && kind === "VIP" ? undefined : numeric || 1,
        durationUnit: kind === "VIP" ? vipUnit : undefined,
        note: note.trim() || undefined
      });
      setRevealedTitle("Chave criada");
      setRevealed(result.key.value);
      setCreateOpen(false);
      await Promise.all([loadKeys(selected), loadMenus()]);
    }, "Não foi possível gerar");
  }

  function viewExistingKey(key: App1MenuKey) {
    if (!canRevealKey(key)) {
      Alert.alert(
        "Valor não recuperável",
        "Esta chave foi criada antes da recuperação segura existir. O servidor possui somente o hash antigo, então o valor original não pode ser reconstruído."
      );
      return;
    }
    runLocked(async () => {
      const result = await revealApp1MenuKey(sessionToken, deviceToken, key.id);
      setRevealedTitle(`${key.kind} • ${key.key_hint}`);
      setRevealed(result.key.value);
    }, "Não foi possível ver a chave").catch(() => {});
  }

  function copyExistingKey(key: App1MenuKey) {
    if (!canRevealKey(key)) {
      Alert.alert(
        "Valor não recuperável",
        "Esta chave antiga não possui uma cópia recuperável no servidor. Ela continua válida normalmente, mas só o hash foi armazenado quando foi criada."
      );
      return;
    }
    runLocked(async () => {
      const result = await revealApp1MenuKey(sessionToken, deviceToken, key.id);
      await Clipboard.setStringAsync(result.key.value);
      Alert.alert(
        "Chave copiada",
        "O App 1 não salvou a chave localmente. A cópia foi enviada apenas para a área de transferência do sistema."
      );
    }, "Não foi possível copiar").catch(() => {});
  }

  function closeRevealed() {
    setRevealed(null);
    setRevealedTitle("Chave");
  }

  function openRenewal(key: App1MenuKey) {
    if (actionLock.current || key.status === "REVOKED") return;
    setRenewTarget(key);
    if (key.kind === "FREE") {
      setRenewDurationValue(String(Math.min(24, Math.max(1, key.duration_value || 24))));
      setRenewVipUnit("DAYS");
      return;
    }

    const unit: VipUnit = key.duration_unit === "MONTHS" || key.duration_unit === "PERMANENT"
      ? key.duration_unit
      : "DAYS";
    setRenewVipUnit(unit);
    setRenewDurationValue(String(Math.max(1, key.duration_value || (unit === "MONTHS" ? 1 : 30))));
  }

  function closeRenewal() {
    if (busy) return;
    setRenewTarget(null);
  }

  async function performRenewal() {
    if (!renewTarget || actionLock.current) return;

    if (renewTarget.kind === "FREE") {
      const hours = positiveInteger(renewDurationValue);
      if (hours === null || hours > 24) {
        Alert.alert("Duração inválida", "Escolha de 1 a 24 horas para o próximo ciclo FREE.");
        return;
      }
      await runLocked(async () => {
        await releaseApp1FreeKey(sessionToken, deviceToken, renewTarget.id, hours);
        setRenewTarget(null);
        await loadKeys();
        Alert.alert("FREE liberada", `O próximo ciclo terá ${hours}h e começará no próximo uso da chave.`);
      }, "Falha ao liberar");
      return;
    }

    const value = renewVipUnit === "PERMANENT" ? undefined : positiveInteger(renewDurationValue);
    if (renewVipUnit !== "PERMANENT" && value === null) {
      Alert.alert("Validade inválida", "Digite um número inteiro maior que zero.");
      return;
    }

    await runLocked(async () => {
      await configureApp1VipKey(sessionToken, deviceToken, renewTarget.id, renewVipUnit, value || undefined);
      setRenewTarget(null);
      await loadKeys();
      Alert.alert(
        "VIP configurada",
        renewVipUnit === "PERMANENT"
          ? "A chave foi configurada como permanente e a nova validade começa no próximo uso."
          : "A nova validade começa no próximo uso da chave."
      );
    }, "Falha ao configurar VIP");
  }

  function submitRenewal() {
    if (!renewTarget || actionLock.current) return;
    const isRestartingActiveVip = renewTarget.kind === "VIP" && renewTarget.access_state === "ACTIVE";
    if (!isRestartingActiveVip) {
      performRenewal().catch(() => {});
      return;
    }

    Alert.alert(
      "Reiniciar VIP ativa",
      "As sessões atuais desta chave serão encerradas. A nova validade começará no próximo uso.",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Reiniciar", style: "destructive", onPress: () => { performRenewal().catch(() => {}); } }
      ]
    );
  }

  function resetDevice(key: App1MenuKey) {
    Alert.alert(
      "Trocar aparelho",
      "As sessões atuais desta chave serão encerradas. O próximo aparelho que usar a chave ficará vinculado a ela. O tempo de acesso já iniciado não é reiniciado por esta ação.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Desvincular",
          style: "destructive",
          onPress: () => {
            runLocked(async () => {
              await resetApp1MenuKeyDevice(sessionToken, deviceToken, key.id);
              await loadKeys();
            }, "Falha").catch(() => {});
          }
        }
      ]
    );
  }

  async function toggleKey(key: App1MenuKey) {
    await runLocked(async () => {
      const action = key.status === "ACTIVE" ? "suspend" : "restore";
      await setApp1MenuKeyState(sessionToken, deviceToken, key.id, action);
      await loadKeys();
    }, "Falha");
  }

  function revokeKey(key: App1MenuKey) {
    Alert.alert("Revogar chave", "Esta ação encerra as sessões da chave e não pode ser desfeita.", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Revogar",
        style: "destructive",
        onPress: () => {
          runLocked(async () => {
            await setApp1MenuKeyState(sessionToken, deviceToken, key.id, "revoke");
            await loadKeys();
          }, "Falha").catch(() => {});
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
          <Pressable key={menu.id} style={s.menuCard} disabled={loading} onPress={() => openMenu(menu)}>
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
        <Pressable style={s.back} disabled={busy} onPress={() => { setSelected(null); setKeys([]); }}>
          <Text style={s.backText}>‹ MENUS</Text>
        </Pressable>
        <View style={s.headerActions}>
          <Pressable style={[s.smallButton, busy && s.disabled]} disabled={busy} onPress={() => { copySelectedLoader().catch(() => {}); }}>
            <Text style={s.smallButtonText}>COPIAR LOADSTRING</Text>
          </Pressable>
          <Pressable style={[s.add, busy && s.disabled]} disabled={busy} onPress={openCreate}>
            <Text style={s.addText}>＋ CHAVE</Text>
          </Pressable>
        </View>
      </View>

      <View style={s.infoCard}>
        <Text style={s.infoTitle}>{selected.name}</Text>
        <Text style={s.infoText}>{selected.public_id} • {usable} utilizável(is) • {keys.length} total</Text>
      </View>

      {keysLoading ? <ActivityIndicator style={{ marginTop: 24 }} /> : keys.length === 0 ? (
        <Text style={s.empty}>Nenhuma chave cadastrada neste menu.</Text>
      ) : keys.map((key) => {
        const recoverable = canRevealKey(key);
        const legacyUnrecoverable = !(key as RevealableMenuKey).can_reveal;
        return (
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
                {legacyUnrecoverable ? <Text style={s.legacyNote}>CHAVE ANTIGA • valor completo não recuperável</Text> : null}
              </View>
            </View>

            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.actions}>
              {recoverable ? <Action label="VER CHAVE" disabled={busy} onPress={() => viewExistingKey(key)} /> : null}
              {recoverable ? <Action label="COPIAR CHAVE" disabled={busy} onPress={() => copyExistingKey(key)} /> : null}
              {key.kind === "FREE" && key.access_state === "WAITING_ADMIN" && key.status !== "REVOKED" ? (
                <Action label="LIBERAR FREE" disabled={busy} onPress={() => openRenewal(key)} />
              ) : null}
              {key.kind === "VIP" && key.status !== "REVOKED" ? (
                <Action
                  label={key.access_state === "EXPIRED" ? "RENOVAR VIP" : "RECONFIGURAR VIP"}
                  disabled={busy}
                  onPress={() => openRenewal(key)}
                />
              ) : null}
              {key.bound_device && key.status !== "REVOKED" ? <Action label="TROCAR CELULAR" disabled={busy} onPress={() => resetDevice(key)} /> : null}
              {key.status !== "REVOKED" ? <Action label={key.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"} disabled={busy} onPress={() => toggleKey(key)} /> : null}
              {key.status !== "REVOKED" ? <Action label="REVOGAR" danger disabled={busy} onPress={() => revokeKey(key)} /> : null}
            </ScrollView>
          </View>
        );
      })}

      <Modal visible={createOpen} transparent animationType="fade" onRequestClose={() => { if (!busy) setCreateOpen(false); }}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <Text style={s.modalTitle}>Gerar chave</Text>
            <View style={s.choiceRow}>
              <Choice label="FREE" active={kind === "FREE"} disabled={busy} onPress={() => { setKind("FREE"); setDurationValue("24"); }} />
              <Choice label="VIP" active={kind === "VIP"} disabled={busy} onPress={() => { setKind("VIP"); setDurationValue("30"); setVipUnit("DAYS"); }} />
            </View>

            {kind === "FREE" ? (
              <>
                <Text style={s.label}>HORAS DE ACESSO • MÁXIMO 24H</Text>
                <TextInput value={durationValue} editable={!busy} onChangeText={setDurationValue} keyboardType="number-pad" style={s.input} placeholder="24" placeholderTextColor="#666" />
                <Text style={s.help}>Depois do período, a chave entra em AGUARDA ADM. Somente um ADM/DEV do App 1 pode liberar outro ciclo.</Text>
              </>
            ) : (
              <>
                <Text style={s.label}>VALIDADE VIP</Text>
                <View style={s.choiceRow}>
                  <Choice label="DIAS" active={vipUnit === "DAYS"} disabled={busy} onPress={() => setVipUnit("DAYS")} />
                  <Choice label="MESES" active={vipUnit === "MONTHS"} disabled={busy} onPress={() => setVipUnit("MONTHS")} />
                  <Choice label="PERMANENTE" active={vipUnit === "PERMANENT"} disabled={busy} onPress={() => setVipUnit("PERMANENT")} />
                </View>
                {vipUnit !== "PERMANENT" ? <TextInput value={durationValue} editable={!busy} onChangeText={setDurationValue} keyboardType="number-pad" style={s.input} placeholder="30" placeholderTextColor="#666" /> : null}
              </>
            )}

            <TextInput value={note} editable={!busy} onChangeText={setNote} style={s.input} placeholder="Observação opcional" placeholderTextColor="#666" />
            <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={createKey}>
              <Text style={s.primaryText}>{busy ? "GERANDO..." : "GERAR CHAVE"}</Text>
            </Pressable>
            <Pressable style={[s.secondary, busy && s.disabled]} disabled={busy} onPress={() => setCreateOpen(false)}>
              <Text style={s.secondaryText}>CANCELAR</Text>
            </Pressable>
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(renewTarget)} transparent animationType="fade" onRequestClose={closeRenewal}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <Text style={s.modalTitle}>{renewTarget?.kind === "FREE" ? "Liberar novo ciclo FREE" : "Configurar VIP"}</Text>
            {renewTarget?.kind === "FREE" ? (
              <>
                <Text style={s.help}>Escolha a duração do próximo ciclo. Ele começa somente quando a chave for usada novamente.</Text>
                <Text style={s.label}>HORAS • 1 A 24</Text>
                <TextInput value={renewDurationValue} editable={!busy} onChangeText={setRenewDurationValue} keyboardType="number-pad" style={s.input} placeholder="24" placeholderTextColor="#666" />
              </>
            ) : (
              <>
                <Text style={s.help}>Você pode mudar a VIP para dias, meses ou permanente a cada renovação/reconfiguração.</Text>
                {renewTarget?.access_state === "ACTIVE" ? <Text style={s.warning}>ATENÇÃO: esta chave está ativa. Salvar a nova configuração encerra as sessões atuais e reinicia a validade no próximo uso.</Text> : null}
                <Text style={s.label}>NOVA VALIDADE VIP</Text>
                <View style={s.choiceRow}>
                  <Choice label="DIAS" active={renewVipUnit === "DAYS"} disabled={busy} onPress={() => setRenewVipUnit("DAYS")} />
                  <Choice label="MESES" active={renewVipUnit === "MONTHS"} disabled={busy} onPress={() => setRenewVipUnit("MONTHS")} />
                  <Choice label="PERMANENTE" active={renewVipUnit === "PERMANENT"} disabled={busy} onPress={() => setRenewVipUnit("PERMANENT")} />
                </View>
                {renewVipUnit !== "PERMANENT" ? (
                  <TextInput value={renewDurationValue} editable={!busy} onChangeText={setRenewDurationValue} keyboardType="number-pad" style={s.input} placeholder={renewVipUnit === "MONTHS" ? "1" : "30"} placeholderTextColor="#666" />
                ) : null}
              </>
            )}
            <Pressable style={[s.primary, busy && s.disabled]} disabled={busy} onPress={submitRenewal}>
              <Text style={s.primaryText}>{busy ? "SALVANDO..." : renewTarget?.kind === "FREE" ? "LIBERAR CICLO" : "SALVAR VIP"}</Text>
            </Pressable>
            <Pressable style={[s.secondary, busy && s.disabled]} disabled={busy} onPress={closeRenewal}>
              <Text style={s.secondaryText}>CANCELAR</Text>
            </Pressable>
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(revealed)} transparent animationType="fade" onRequestClose={closeRevealed}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <Text style={s.modalTitle}>{revealedTitle}</Text>
            <Text style={s.help}>O valor foi buscado diretamente do servidor para esta ação e não é salvo no armazenamento local do App 1.</Text>
            <Text selectable style={s.secret}>{revealed}</Text>
            <Pressable style={s.primary} onPress={async () => {
              if (!revealed) return;
              await Clipboard.setStringAsync(revealed);
              Alert.alert("Chave copiada", "A cópia foi enviada para a área de transferência do sistema.");
            }}>
              <Text style={s.primaryText}>COPIAR CHAVE</Text>
            </Pressable>
            <Pressable style={s.secondary} onPress={closeRevealed}>
              <Text style={s.secondaryText}>FECHAR E LIMPAR DA TELA</Text>
            </Pressable>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function Action({ label, onPress, danger = false, disabled = false }: {
  label: string;
  onPress: () => void;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <Pressable
      style={[s.action, danger && s.actionDanger, disabled && s.disabled]}
      onPress={onPress}
      disabled={disabled}
    >
      <Text style={[s.actionText, danger && s.dangerText]}>{label}</Text>
    </Pressable>
  );
}

function Choice({ label, active, onPress, disabled = false }: {
  label: string;
  active: boolean;
  onPress: () => void;
  disabled?: boolean;
}) {
  return (
    <Pressable
      style={[s.choice, active && s.choiceActive, disabled && s.disabled]}
      onPress={onPress}
      disabled={disabled}
    >
      <Text style={[s.choiceText, active && s.choiceTextActive]}>{label}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  infoCard: { borderRadius: 15, borderWidth: 1, borderColor: "#2A2A30", backgroundColor: "#0A0A0DB8", padding: 14, marginBottom: 10 },
  infoTitle: { color: "#FFF", fontSize: 17, fontWeight: "900" },
  infoText: { color: "#95959C", fontSize: 11, lineHeight: 17, marginTop: 5 },
  empty: { color: "#76767D", fontSize: 12, textAlign: "center", marginTop: 28 },
  menuCard: { flexDirection: "row", gap: 12, alignItems: "center", borderRadius: 14, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#09090BA6", padding: 14, marginBottom: 8 },
  keyCard: { borderRadius: 14, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#09090BA6", padding: 13, marginBottom: 9 },
  keyTop: { flexDirection: "row", gap: 10 },
  badgeRow: { flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 5 },
  kind: { color: "#65D97F", fontSize: 9, fontWeight: "900" },
  vip: { color: "#D49CFF" },
  ok: { color: "#65D97F", fontSize: 9, fontWeight: "900" },
  bad: { color: "#FF666C", fontSize: 9, fontWeight: "900" },
  title: { color: "#FFF", fontSize: 14, fontWeight: "900" },
  meta: { color: "#83838B", fontSize: 10, lineHeight: 15, marginTop: 2 },
  legacyNote: { color: "#B38A63", fontSize: 8, fontWeight: "900", marginTop: 7 },
  headerRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 9 },
  headerActions: { flexDirection: "row", alignItems: "center", justifyContent: "flex-end", flexWrap: "wrap", gap: 6, flex: 1 },
  back: { paddingVertical: 8, paddingHorizontal: 8 },
  backText: { color: "#B4B4BA", fontSize: 10, fontWeight: "900" },
  add: { minHeight: 38, borderRadius: 10, borderWidth: 1, borderColor: "#414148", backgroundColor: "#0B0B0DA6", paddingHorizontal: 11, alignItems: "center", justifyContent: "center" },
  addText: { color: "#FFF", fontSize: 9, fontWeight: "900" },
  smallButton: { minHeight: 38, borderRadius: 10, borderWidth: 1, borderColor: "#49384F", backgroundColor: "#110C1599", paddingHorizontal: 9, alignItems: "center", justifyContent: "center" },
  smallButtonText: { color: "#D6BAEA", fontSize: 8, fontWeight: "900" },
  actions: { flexDirection: "row", gap: 7, marginTop: 11 },
  action: { borderRadius: 9, borderWidth: 1, borderColor: "#3A3A40", backgroundColor: "#08080A80", paddingHorizontal: 10, paddingVertical: 9 },
  actionDanger: { borderColor: "#542126", backgroundColor: "#130708B8" },
  actionText: { color: "#D0D0D5", fontSize: 8, fontWeight: "900" },
  dangerText: { color: "#FF676E" },
  disabled: { opacity: 0.45 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.76)", alignItems: "center", justifyContent: "center", padding: 16 },
  modalBox: { width: "100%", maxWidth: 520, borderRadius: 18, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#09090CEB", padding: 16 },
  modalTitle: { color: "#FFF", fontSize: 20, fontWeight: "900", marginBottom: 10 },
  label: { color: "#8A8A92", fontSize: 9, fontWeight: "900", letterSpacing: 1.1, marginTop: 11 },
  help: { color: "#94949B", fontSize: 10, lineHeight: 16, marginTop: 7 },
  warning: { color: "#FF8A90", fontSize: 9, lineHeight: 15, marginTop: 9, borderRadius: 10, borderWidth: 1, borderColor: "#51242A", backgroundColor: "#16090BB8", padding: 9 },
  input: { minHeight: 48, borderRadius: 11, borderWidth: 1, borderColor: "#36363C", backgroundColor: "#111114B8", color: "#FFF", paddingHorizontal: 12, marginTop: 9 },
  choiceRow: { flexDirection: "row", gap: 7, flexWrap: "wrap" },
  choice: { borderRadius: 9, borderWidth: 1, borderColor: "#393940", backgroundColor: "#08080A80", paddingHorizontal: 11, paddingVertical: 9 },
  choiceActive: { borderColor: "#FFF", backgroundColor: "#FFF" },
  choiceText: { color: "#96969D", fontSize: 9, fontWeight: "900" },
  choiceTextActive: { color: "#050505" },
  primary: { minHeight: 49, borderRadius: 12, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 13 },
  primaryText: { color: "#050505", fontSize: 10, fontWeight: "900" },
  secondary: { minHeight: 44, alignItems: "center", justifyContent: "center", marginTop: 5 },
  secondaryText: { color: "#9A9AA2", fontSize: 9, fontWeight: "900" },
  secret: { color: "#FFF", backgroundColor: "#111116B8", borderRadius: 11, borderWidth: 1, borderColor: "#3C3C43", padding: 13, fontSize: 12, lineHeight: 18, marginTop: 9 }
});
