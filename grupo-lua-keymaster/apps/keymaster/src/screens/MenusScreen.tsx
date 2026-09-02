import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Modal,
  Pressable,
  SafeAreaView,
  ScrollView,
  Text,
  TextInput,
  View
} from "react-native";
import { StatusBar } from "expo-status-bar";
import * as Clipboard from "expo-clipboard";
import {
  type ManagedMenu,
  type MenuAccessKey,
  type MenuAccessSession,
  type MenuKeyKind,
  createManagedMenu,
  createMenuAccessKey,
  deleteManagedMenu,
  listManagedMenus,
  listMenuAccessKeys,
  listMenuAccessSessions,
  revokeAllMenuAccessSessions,
  revokeMenuAccessSession,
  setManagedMenuState,
  setMenuAccessKeyDuration,
  setMenuAccessKeyState,
  updateManagedMenu
} from "../api";
import { BottomNav } from "../components/BottomNav";
import { Button, Header } from "../components/Common";
import { CredentialModal } from "../components/CredentialModal";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { styles } from "../styles";

type StatusFilter = "ALL" | "ACTIVE" | "SUSPENDED";
type KeyFilter = "ALL" | "FREE" | "VIP" | "ACTIVE" | "SUSPENDED" | "EXPIRED" | "REVOKED";
type SessionFilter = "ALL" | "ACTIVE" | "ENDED";

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function accessUrl(menu: ManagedMenu) {
  return menu.access_url || menu.loader_url;
}

function isExpired(item: MenuAccessKey) {
  if (item.kind !== "FREE" || !item.expires_at) return false;
  const timestamp = new Date(item.expires_at).getTime();
  return Number.isFinite(timestamp) && timestamp <= Date.now();
}

function accessSessionState(item: MenuAccessSession) {
  if (item.active) return "ATIVA";
  if (item.revoked_at) return "REVOGADA";
  return "EXPIRADA";
}

export function MenusScreen({ session, onHome, onAccounts, onAudit, onCritical }: {
  session: string;
  onHome: () => void;
  onAccounts: () => void;
  onAudit: () => void;
  onCritical: () => void;
}) {
  const [menus, setMenus] = useState<ManagedMenu[]>([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("ALL");
  const [createModal, setCreateModal] = useState(false);
  const [name, setName] = useState("");
  const [sourceUrl, setSourceUrl] = useState("");
  const [selected, setSelected] = useState<ManagedMenu | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ManagedMenu | null>(null);
  const [editName, setEditName] = useState("");
  const [editUrl, setEditUrl] = useState("");
  const [keys, setKeys] = useState<MenuAccessKey[]>([]);
  const [keysLoading, setKeysLoading] = useState(false);
  const [keyModal, setKeyModal] = useState(false);
  const [kind, setKind] = useState<MenuKeyKind>("FREE");
  const [durationHours, setDurationHours] = useState("24");
  const [note, setNote] = useState("");
  const [revealedKey, setRevealedKey] = useState<string | null>(null);
  const [durationTarget, setDurationTarget] = useState<MenuAccessKey | null>(null);
  const [newDurationHours, setNewDurationHours] = useState("24");
  const [keyQuery, setKeyQuery] = useState("");
  const [keyFilter, setKeyFilter] = useState<KeyFilter>("ALL");
  const [accessSessions, setAccessSessions] = useState<MenuAccessSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [sessionQuery, setSessionQuery] = useState("");
  const [sessionFilter, setSessionFilter] = useState<SessionFilter>("ALL");

  async function refresh() {
    setLoading(true);
    try {
      const result = await listManagedMenus(session, {
        q: query || undefined,
        status: statusFilter === "ALL" ? undefined : statusFilter
      });
      setMenus(result.menus);
      if (selected) {
        const updated = result.menus.find((item) => item.id === selected.id);
        if (updated) setSelected(updated);
      }
    } catch (error) {
      Alert.alert("Falha ao carregar menus", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => refresh().catch(() => {}), 250);
    return () => clearTimeout(timer);
  }, [session, query, statusFilter]);

  async function create() {
    try {
      await createManagedMenu(session, name, sourceUrl);
      setName("");
      setSourceUrl("");
      setCreateModal(false);
      await refresh();
    } catch (error) {
      Alert.alert("Não foi possível cadastrar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function openMenu(menu: ManagedMenu) {
    setSelected(menu);
    setEditName(menu.name);
    setEditUrl(menu.source_url);
    setKeyQuery("");
    setKeyFilter("ALL");
    setSessionQuery("");
    setSessionFilter("ALL");
    await Promise.all([reloadKeys(menu), reloadAccessSessions(menu)]);
  }

  async function reloadKeys(menu: ManagedMenu) {
    setKeysLoading(true);
    try {
      setKeys((await listMenuAccessKeys(session, menu.id)).keys);
    } catch (error) {
      setKeys([]);
      Alert.alert("Chaves indisponíveis", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setKeysLoading(false);
    }
  }

  async function reloadAccessSessions(menu: ManagedMenu) {
    setSessionsLoading(true);
    try {
      setAccessSessions((await listMenuAccessSessions(session, menu.id)).sessions);
    } catch (error) {
      setAccessSessions([]);
      Alert.alert("Acessos indisponíveis", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setSessionsLoading(false);
    }
  }

  async function saveMenu() {
    if (!selected) return;
    try {
      const result = await updateManagedMenu(session, selected.id, { name: editName, sourceUrl: editUrl });
      setSelected(result.menu);
      setEditName(result.menu.name);
      setEditUrl(result.menu.source_url);
      await refresh();
      Alert.alert("Menu atualizado", "Nome e origem foram salvos pelo servidor.");
    } catch (error) {
      Alert.alert("Falha ao editar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function toggleMenu(menu: ManagedMenu) {
    try {
      const action = menu.status === "ACTIVE" ? "suspend" : "restore";
      const result = await setManagedMenuState(session, menu.id, action);
      if (selected?.id === menu.id) {
        setSelected(result.menu);
        await Promise.all([reloadKeys(menu), reloadAccessSessions(menu)]);
      }
      await refresh();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  function requestMenuToggle(menu: ManagedMenu) {
    if (menu.status !== "ACTIVE") {
      toggleMenu(menu).catch(() => {});
      return;
    }
    Alert.alert(
      "Suspender menu",
      "Novas validações serão bloqueadas e as sessões de acesso já abertas serão revogadas.",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Suspender", style: "destructive", onPress: () => toggleMenu(menu) }
      ]
    );
  }

  function requestMenuDeletion(menu: ManagedMenu) {
    Alert.alert(
      "Excluir menu definitivamente",
      `Excluir ${menu.name}? O menu deixará de aparecer, todas as chaves serão revogadas e todas as sessões serão encerradas. Esta ação não pode ser desfeita pelo painel.`,
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Continuar", style: "destructive", onPress: () => setDeleteTarget(menu) }
      ]
    );
  }

  async function generateKey() {
    if (!selected) return;
    try {
      const hours = Math.max(1, Number(durationHours || 24));
      const result = await createMenuAccessKey(session, selected.id, {
        kind,
        durationHours: kind === "FREE" ? hours : undefined,
        note: note.trim() || undefined
      });
      setRevealedKey(result.key.value);
      setKeyModal(false);
      setNote("");
      setDurationHours("24");
      await Promise.all([reloadKeys(selected), reloadAccessSessions(selected)]);
      await refresh();
    } catch (error) {
      Alert.alert("Não foi possível gerar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function keyAction(item: MenuAccessKey, action: "suspend" | "restore" | "revoke" | "permanent") {
    if (!selected) return;
    try {
      await setMenuAccessKeyState(session, item.id, action);
      await Promise.all([reloadKeys(selected), reloadAccessSessions(selected)]);
      await refresh();
    } catch (error) {
      Alert.alert("Falha na chave", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function changeDuration() {
    if (!selected || !durationTarget) return;
    const hours = Number(newDurationHours);
    if (!Number.isFinite(hours) || hours < 1) {
      Alert.alert("Duração inválida", "Informe pelo menos 1 hora.");
      return;
    }
    try {
      await setMenuAccessKeyDuration(session, durationTarget.id, hours);
      setDurationTarget(null);
      setNewDurationHours("24");
      await Promise.all([reloadKeys(selected), reloadAccessSessions(selected)]);
      await refresh();
    } catch (error) {
      Alert.alert("Falha na duração", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function revokeAccessSession(item: MenuAccessSession) {
    if (!selected) return;
    try {
      await revokeMenuAccessSession(session, item.id);
      await reloadAccessSessions(selected);
      await refresh();
    } catch (error) {
      Alert.alert("Falha ao encerrar acesso", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function revokeAllAccessSessions() {
    if (!selected) return;
    try {
      const result = await revokeAllMenuAccessSessions(session, selected.id);
      await reloadAccessSessions(selected);
      await refresh();
      Alert.alert("Acessos encerrados", `${result.revokedCount} sessão(ões) ativa(s) foram revogadas.`);
    } catch (error) {
      Alert.alert("Falha ao encerrar acessos", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  function requestRevokeAllAccessSessions() {
    if (!selected) return;
    Alert.alert(
      "Encerrar todos os acessos",
      "Todos os tokens de acesso ainda ativos deste menu serão revogados. As chaves FREE/VIP continuam existindo e poderão gerar novas sessões se permanecerem válidas.",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Encerrar todos", style: "destructive", onPress: () => revokeAllAccessSessions() }
      ]
    );
  }

  const normalizedKeyQuery = keyQuery.trim().toLowerCase();
  const visibleKeys = keys.filter((item) => {
    const expired = isExpired(item);
    const matchesQuery = !normalizedKeyQuery ||
      item.key_hint.toLowerCase().includes(normalizedKeyQuery) ||
      String(item.note || "").toLowerCase().includes(normalizedKeyQuery);
    if (!matchesQuery) return false;

    if (keyFilter === "FREE") return item.kind === "FREE";
    if (keyFilter === "VIP") return item.kind === "VIP";
    if (keyFilter === "ACTIVE") return item.status === "ACTIVE" && !expired && item.usable !== false;
    if (keyFilter === "SUSPENDED") return item.status === "SUSPENDED";
    if (keyFilter === "EXPIRED") return expired || (item.status === "ACTIVE" && item.usable === false);
    if (keyFilter === "REVOKED") return item.status === "REVOKED";
    return true;
  });

  const normalizedSessionQuery = sessionQuery.trim().toLowerCase();
  const visibleAccessSessions = accessSessions.filter((item) => {
    const matchesQuery = !normalizedSessionQuery ||
      String(item.client_label || "").toLowerCase().includes(normalizedSessionQuery) ||
      item.key_hint.toLowerCase().includes(normalizedSessionQuery) ||
      String(item.key_note || "").toLowerCase().includes(normalizedSessionQuery);
    if (!matchesQuery) return false;
    if (sessionFilter === "ACTIVE") return item.active;
    if (sessionFilter === "ENDED") return !item.active;
    return true;
  });

  const usableKeys = keys.filter((item) => item.status === "ACTIVE" && item.usable !== false && !isExpired(item)).length;
  const totalKeyUses = keys.reduce((sum, item) => sum + Number(item.use_count || 0), 0);
  const activeAccessSessions = accessSessions.filter((item) => item.active).length;

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <View style={styles.screenBody}>
          <Header title="MENUS & CHAVES" onBack={onHome} />
          <View style={styles.listHeaderCompact}>
            <View style={{ flex: 1 }}>
              <Text style={styles.screenTitle}>Chaves</Text>
              <Text style={styles.muted}>Cadastre menus e administre acessos FREE/VIP sem colocar a lista de chaves no código cliente.</Text>
            </View>
            <Pressable style={styles.addButton} onPress={() => setCreateModal(true)}><Text style={styles.add}>＋</Text></Pressable>
          </View>

          <TextInput
            value={query}
            onChangeText={setQuery}
            style={styles.searchInput}
            placeholder="Buscar menus..."
            placeholderTextColor="#6D6D73"
            autoCapitalize="none"
            autoCorrect={false}
          />

          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
            {(["ALL", "ACTIVE", "SUSPENDED"] as StatusFilter[]).map((item) => (
              <Pressable key={item} style={[styles.filterChip, statusFilter === item && styles.filterChipActive]} onPress={() => setStatusFilter(item)}>
                <Text style={[styles.filterChipText, statusFilter === item && styles.filterChipTextActive]}>
                  {item === "ALL" ? "TODOS" : item === "ACTIVE" ? "ATIVOS" : "SUSPENSOS"}
                </Text>
              </Pressable>
            ))}
          </ScrollView>

          {loading ? <ActivityIndicator style={{ marginTop: 30 }} /> : (
            <FlatList
              data={menus}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.accountList}
              ListEmptyComponent={<Text style={styles.empty}>Nenhum menu cadastrado.</Text>}
              renderItem={({ item }) => (
                <View style={styles.accountCard}>
                  <Pressable onPress={() => openMenu(item)} style={styles.accountTop}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={styles.cardTitle}>{item.name}</Text>
                        <Text style={styles.badge}>{item.public_id}</Text>
                      </View>
                      <Text style={styles.accountMeta} numberOfLines={1}>{item.source_url}</Text>
                      <Text style={styles.accountMeta}>{item.accesses_month} acessos no mês</Text>
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : styles.suspended}>{item.status === "ACTIVE" ? "ATIVO" : "SUSPENSO"}</Text>
                  </Pressable>

                  <View style={styles.detailGrid}>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>FREE</Text><Text style={styles.detailValue}>{item.free_keys}</Text></View>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>VIP</Text><Text style={styles.detailValue}>{item.vip_keys}</Text></View>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>ONLINE</Text><Text style={styles.detailValue}>{item.active_accesses}</Text></View>
                  </View>

                  <View style={styles.credentialBox}>
                    <Text style={styles.credentialText} numberOfLines={2}>{accessUrl(item)}</Text>
                  </View>
                  <View style={styles.rowGap}>
                    <Pressable style={styles.smallAction} onPress={() => Clipboard.setStringAsync(accessUrl(item))}>
                      <Text style={styles.smallActionText}>COPIAR URL</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => openMenu(item)}>
                      <Text style={styles.smallActionText}>GERENCIAR</Text>
                    </Pressable>
                    <Pressable style={[styles.smallAction, item.status === "ACTIVE" && styles.smallDanger]} onPress={() => requestMenuToggle(item)}>
                      <Text style={item.status === "ACTIVE" ? styles.smallDangerText : styles.smallActionText}>{item.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"}</Text>
                    </Pressable>
                  </View>
                </View>
              )}
            />
          )}
        </View>
        <BottomNav current="menus" onHome={onHome} onAccounts={onAccounts} onMenus={() => {}} onAudit={onAudit} onCritical={onCritical} />
      </View>

      <Modal visible={createModal} transparent animationType="fade" onRequestClose={() => setCreateModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Cadastrar novo menu</Text>
            <Text style={styles.muted}>Informe um nome e a URL HTTPS do arquivo .lua no GitHub.</Text>
            <TextInput value={name} onChangeText={setName} style={styles.input} placeholder="Nome do menu" placeholderTextColor="#666" />
            <TextInput value={sourceUrl} onChangeText={setSourceUrl} style={styles.input} placeholder="https://github.com/.../Menu.lua" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
            <Button title="CADASTRAR MENU" onPress={create} disabled={name.trim().length < 2 || !sourceUrl.trim()} />
            <Button title="FECHAR" onPress={() => setCreateModal(false)} secondary />
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(selected)} transparent animationType="slide" onRequestClose={() => setSelected(null)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalBox, styles.detailModal]}>
            {selected ? (
              <ScrollView>
                <View style={styles.detailHeader}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.cardTitle}>{selected.name}</Text>
                    <Text style={styles.accountMeta}>{selected.public_id} • {selected.status}</Text>
                  </View>
                  <Pressable onPress={() => setSelected(null)}><Text style={styles.closeText}>✕</Text></Pressable>
                </View>

                <View style={styles.detailGrid}>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>CHAVES</Text><Text style={styles.detailValue}>{keys.length}</Text></View>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>UTILIZÁVEIS</Text><Text style={styles.detailValue}>{usableKeys}</Text></View>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>ONLINE</Text><Text style={styles.detailValue}>{activeAccessSessions}</Text></View>
                </View>
                <Text style={styles.accountMeta}>Usos acumulados das chaves: {totalKeyUses}</Text>

                <Text style={styles.section}>URL DE ACESSO</Text>
                <View style={styles.credentialBox}>
                  <Text style={styles.credentialText}>{accessUrl(selected)}</Text>
                </View>
                <Button title="COPIAR URL DE ACESSO" onPress={() => Clipboard.setStringAsync(accessUrl(selected))} secondary />

                <Text style={styles.section}>CONFIGURAÇÃO</Text>
                <TextInput value={editName} onChangeText={setEditName} style={styles.input} placeholder="Nome" placeholderTextColor="#666" />
                <TextInput value={editUrl} onChangeText={setEditUrl} style={styles.input} placeholder="URL GitHub" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
                <Button title="SALVAR ALTERAÇÕES" onPress={saveMenu} secondary />

                <View style={styles.detailSectionRow}>
                  <Text style={styles.sectionInline}>SESSÕES DE ACESSO</Text>
                  <Pressable onPress={() => reloadAccessSessions(selected)}><Text style={styles.refreshLink}>↻ ATUALIZAR</Text></Pressable>
                </View>
                <Text style={styles.muted}>O Keymaster mostra somente metadados administrativos. O token secreto de acesso nunca é exibido nesta tela.</Text>

                <View style={styles.rowGap}>
                  <Pressable style={styles.smallAction} onPress={() => setSessionFilter("ACTIVE")}>
                    <Text style={styles.smallActionText}>{activeAccessSessions} ONLINE</Text>
                  </Pressable>
                  <Pressable style={[styles.smallAction, activeAccessSessions > 0 && styles.smallDanger]} disabled={activeAccessSessions === 0} onPress={requestRevokeAllAccessSessions}>
                    <Text style={activeAccessSessions > 0 ? styles.smallDangerText : styles.smallActionText}>ENCERRAR TODAS</Text>
                  </Pressable>
                </View>

                <TextInput
                  value={sessionQuery}
                  onChangeText={setSessionQuery}
                  style={styles.searchInput}
                  placeholder="Buscar cliente, chave ou observação..."
                  placeholderTextColor="#6D6D73"
                  autoCapitalize="none"
                  autoCorrect={false}
                />

                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
                  {(["ALL", "ACTIVE", "ENDED"] as SessionFilter[]).map((item) => (
                    <Pressable key={item} style={[styles.filterChip, sessionFilter === item && styles.filterChipActive]} onPress={() => setSessionFilter(item)}>
                      <Text style={[styles.filterChipText, sessionFilter === item && styles.filterChipTextActive]}>
                        {item === "ALL" ? "TODAS" : item === "ACTIVE" ? "ATIVAS" : "ENCERRADAS"}
                      </Text>
                    </Pressable>
                  ))}
                </ScrollView>

                {sessionsLoading ? <ActivityIndicator style={{ marginVertical: 22 }} /> : visibleAccessSessions.length === 0 ? (
                  <Text style={styles.emptyCompact}>{accessSessions.length === 0 ? "Nenhuma sessão de acesso registrada." : "Nenhuma sessão corresponde aos filtros."}</Text>
                ) : visibleAccessSessions.map((item) => (
                  <View key={item.id} style={styles.sessionCard}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={[styles.badge, item.key_kind === "VIP" && { color: "#D49CFF" }]}>{item.key_kind}</Text>
                        <Text style={item.active ? styles.active : styles.sessionOff}>{accessSessionState(item)}</Text>
                      </View>
                      <Text style={styles.sessionTitle}>{item.client_label || "Cliente sem identificação"}</Text>
                      <Text style={styles.accountMeta}>{item.key_hint}{item.key_note ? ` • ${item.key_note}` : ""}</Text>
                      <Text style={styles.accountMeta}>Criada {formatDate(item.created_at)} • expira {formatDate(item.expires_at)}</Text>
                      <Text style={styles.accountMeta}>Último sinal {formatDate(item.last_seen_at)}</Text>
                    </View>
                    {item.active ? (
                      <Pressable style={styles.revokeButton} onPress={() => {
                        Alert.alert("Encerrar acesso", `Revogar a sessão de ${item.client_label || "cliente sem identificação"}?`, [
                          { text: "Cancelar", style: "cancel" },
                          { text: "Encerrar", style: "destructive", onPress: () => revokeAccessSession(item) }
                        ]);
                      }}>
                        <Text style={styles.revokeButtonText}>ENCERRAR</Text>
                      </Pressable>
                    ) : null}
                  </View>
                ))}

                <View style={styles.detailSectionRow}>
                  <Text style={styles.sectionInline}>CHAVES FREE/VIP</Text>
                  <Pressable onPress={() => setKeyModal(true)}><Text style={styles.refreshLink}>＋ GERAR CHAVE</Text></Pressable>
                </View>

                <TextInput
                  value={keyQuery}
                  onChangeText={setKeyQuery}
                  style={styles.searchInput}
                  placeholder="Buscar por dica ou observação..."
                  placeholderTextColor="#6D6D73"
                  autoCapitalize="none"
                  autoCorrect={false}
                />

                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
                  {(["ALL", "FREE", "VIP", "ACTIVE", "SUSPENDED", "EXPIRED", "REVOKED"] as KeyFilter[]).map((item) => (
                    <Pressable key={item} style={[styles.filterChip, keyFilter === item && styles.filterChipActive]} onPress={() => setKeyFilter(item)}>
                      <Text style={[styles.filterChipText, keyFilter === item && styles.filterChipTextActive]}>
                        {item === "ALL" ? "TODAS" : item === "ACTIVE" ? "ATIVAS" : item === "SUSPENDED" ? "SUSPENSAS" : item === "EXPIRED" ? "EXPIRADAS" : item === "REVOKED" ? "REVOGADAS" : item}
                      </Text>
                    </Pressable>
                  ))}
                </ScrollView>

                {keysLoading ? <ActivityIndicator style={{ marginVertical: 22 }} /> : visibleKeys.length === 0 ? (
                  <Text style={styles.emptyCompact}>{keys.length === 0 ? "Nenhuma chave criada." : "Nenhuma chave corresponde aos filtros."}</Text>
                ) : visibleKeys.map((item) => (
                  <View key={item.id} style={styles.sessionCard}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={[styles.badge, item.kind === "VIP" && { color: "#D49CFF" }]}>{item.kind}</Text>
                        <Text style={item.status === "ACTIVE" && item.usable !== false && !isExpired(item) ? styles.active : styles.sessionOff}>
                          {item.status === "ACTIVE" && item.usable !== false && !isExpired(item) ? "ATIVA" : item.status === "REVOKED" ? "REVOGADA" : isExpired(item) || item.usable === false ? "EXPIRADA" : "SUSPENSA"}
                        </Text>
                      </View>
                      <Text style={styles.sessionTitle}>{item.key_hint}</Text>
                      <Text style={styles.accountMeta}>
                        {item.kind === "FREE" ? `Expira ${formatDate(item.expires_at)}` : "Permanente"}
                        {item.note ? ` • ${item.note}` : ""}
                      </Text>
                      <Text style={styles.accountMeta}>
                        {Number(item.use_count || 0)} usos • último uso {formatDate(item.last_used_at)}
                      </Text>
                    </View>
                    {item.status !== "REVOKED" ? (
                      <View style={{ gap: 6 }}>
                        <Pressable style={styles.revokeButton} onPress={() => keyAction(item, item.status === "ACTIVE" ? "suspend" : "restore")}>
                          <Text style={styles.revokeButtonText}>{item.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"}</Text>
                        </Pressable>
                        {item.kind === "FREE" ? (
                          <>
                            <Pressable style={styles.revokeButton} onPress={() => { setDurationTarget(item); setNewDurationHours("24"); }}>
                              <Text style={styles.revokeButtonText}>DURAÇÃO</Text>
                            </Pressable>
                            <Pressable style={styles.revokeButton} onPress={() => keyAction(item, "permanent")}>
                              <Text style={styles.revokeButtonText}>TORNAR VIP</Text>
                            </Pressable>
                          </>
                        ) : null}
                        <Pressable style={styles.revokeButton} onPress={() => {
                          Alert.alert("Revogar chave", "A revogação é definitiva para esta autorização.", [
                            { text: "Cancelar", style: "cancel" },
                            { text: "Revogar", style: "destructive", onPress: () => keyAction(item, "revoke") }
                          ]);
                        }}><Text style={styles.revokeButtonText}>REVOGAR</Text></Pressable>
                      </View>
                    ) : null}
                  </View>
                ))}

                <Button title={selected.status === "ACTIVE" ? "SUSPENDER MENU" : "LIBERAR MENU"} danger={selected.status === "ACTIVE"} secondary={selected.status !== "ACTIVE"} onPress={() => requestMenuToggle(selected)} />
                <Button title="EXCLUIR MENU DEFINITIVAMENTE" danger onPress={() => requestMenuDeletion(selected)} />
                <Text style={styles.muted}>A exclusão exige uma conta DEV ativa. O servidor revoga as chaves e sessões, marca o menu como removido e preserva apenas os registros necessários de auditoria.</Text>
              </ScrollView>
            ) : null}
          </View>
        </View>
      </Modal>

      <Modal visible={keyModal} transparent animationType="fade" onRequestClose={() => setKeyModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Gerar chave de acesso</Text>
            <View style={styles.rowGap}>
              <Pressable style={[styles.halfButton, kind === "FREE" && styles.selected]} onPress={() => setKind("FREE")}><Text style={styles.halfButtonText}>FREE</Text></Pressable>
              <Pressable style={[styles.halfButton, kind === "VIP" && styles.selected]} onPress={() => setKind("VIP")}><Text style={styles.halfButtonText}>VIP</Text></Pressable>
            </View>
            {kind === "FREE" ? (
              <TextInput value={durationHours} onChangeText={setDurationHours} style={styles.input} keyboardType="numeric" placeholder="Duração em horas (padrão 24)" placeholderTextColor="#666" />
            ) : <Text style={styles.muted}>VIP não expira automaticamente; permanece válida até suspensão ou revogação.</Text>}
            <TextInput value={note} onChangeText={setNote} style={styles.input} placeholder="Observação opcional" placeholderTextColor="#666" />
            <Button title="GERAR CHAVE" onPress={generateKey} />
            <Button title="FECHAR" onPress={() => setKeyModal(false)} secondary />
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(durationTarget)} transparent animationType="fade" onRequestClose={() => setDurationTarget(null)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Alterar duração FREE</Text>
            <Text style={styles.muted}>A nova validade é recalculada pelo relógio do servidor a partir de agora.</Text>
            <TextInput value={newDurationHours} onChangeText={setNewDurationHours} style={styles.input} keyboardType="numeric" placeholder="Horas" placeholderTextColor="#666" />
            <Button title="ATUALIZAR DURAÇÃO" onPress={changeDuration} />
            <Button title="CANCELAR" onPress={() => setDurationTarget(null)} secondary />
          </View>
        </View>
      </Modal>

      <CredentialModal credential={revealedKey} onClose={() => setRevealedKey(null)} />
      <DevAuthorizationModal
        visible={Boolean(deleteTarget)}
        session={session}
        action="DELETE_MANAGED_MENU"
        targetId={deleteTarget?.id}
        title={deleteTarget ? `Excluir ${deleteTarget.name}` : "Excluir menu"}
        onCancel={() => setDeleteTarget(null)}
        onAuthorized={async (authorizationToken) => {
          if (!deleteTarget) return;
          const targetName = deleteTarget.name;
          const result = await deleteManagedMenu(session, deleteTarget.id, authorizationToken);
          setDeleteTarget(null);
          setSelected(null);
          setKeys([]);
          setAccessSessions([]);
          await refresh();
          Alert.alert(
            "Menu excluído",
            `${targetName} foi removido. ${result.revokedKeys} chave(s) e ${result.revokedSessions} sessão(ões) foram revogadas no processo.`
          );
        }}
      />
    </SafeAreaView>
  );
}
