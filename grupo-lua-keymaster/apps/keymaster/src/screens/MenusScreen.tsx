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
  type MenuKeyKind,
  createManagedMenu,
  createMenuAccessKey,
  deleteManagedMenu,
  listManagedMenus,
  listMenuAccessKeys,
  setManagedMenuState,
  setMenuAccessKeyDuration,
  setMenuAccessKeyState,
  updateManagedMenu
} from "../api";
import { BottomNav } from "../components/BottomNav";
import { Button, Header } from "../components/Common";
import { CredentialModal } from "../components/CredentialModal";
import { styles } from "../styles";

type StatusFilter = "ALL" | "ACTIVE" | "SUSPENDED";

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function loaderText(menu: ManagedMenu) {
  return menu.loadstring || `loadstring(game:HttpGet("${menu.loader_url}"))()`;
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
    await reloadKeys(menu);
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
        await reloadKeys(result.menu);
      }
      await refresh();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function deleteMenu(menu: ManagedMenu) {
    try {
      await deleteManagedMenu(session, menu.id);
      setSelected(null);
      setKeys([]);
      await refresh();
      Alert.alert("Menu excluído", "O cadastro foi removido e os acessos associados foram invalidados.");
    } catch (error) {
      Alert.alert("Falha ao excluir", error instanceof Error ? error.message : "Erro desconhecido");
    }
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
      await reloadKeys(selected);
      await refresh();
    } catch (error) {
      Alert.alert("Não foi possível gerar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function keyAction(item: MenuAccessKey, action: "suspend" | "restore" | "revoke" | "permanent") {
    if (!selected) return;
    try {
      await setMenuAccessKeyState(session, item.id, action);
      await reloadKeys(selected);
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
      await reloadKeys(selected);
      await refresh();
    } catch (error) {
      Alert.alert("Falha na duração", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

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
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : styles.suspended}>{item.status === "ACTIVE" ? "ATIVO" : "SUSPENSO"}</Text>
                  </Pressable>

                  <View style={styles.detailGrid}>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>FREE</Text><Text style={styles.detailValue}>{item.free_keys}</Text></View>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>VIP</Text><Text style={styles.detailValue}>{item.vip_keys}</Text></View>
                    <View style={styles.detailCell}><Text style={styles.detailLabel}>EXECUÇÕES</Text><Text style={styles.detailValue}>{item.accesses_month}</Text></View>
                  </View>

                  <View style={styles.credentialBox}>
                    <Text style={styles.credentialText} numberOfLines={3}>{loaderText(item)}</Text>
                  </View>
                  <View style={styles.rowGap}>
                    <Pressable style={styles.smallAction} onPress={() => Clipboard.setStringAsync(loaderText(item))}>
                      <Text style={styles.smallActionText}>COPIAR LOADSTRING</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => openMenu(item)}>
                      <Text style={styles.smallActionText}>CHAVES</Text>
                    </Pressable>
                    <Pressable style={[styles.smallAction, item.status === "ACTIVE" && styles.smallDanger]} onPress={() => toggleMenu(item)}>
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

                <Text style={styles.sectionInline}>LOADSTRING DE ACESSO</Text>
                <View style={styles.credentialBox}>
                  <Text style={styles.credentialText}>{loaderText(selected)}</Text>
                </View>
                <Button title="COPIAR LOADSTRING" onPress={() => Clipboard.setStringAsync(loaderText(selected))} secondary />

                <Text style={styles.section}>CONFIGURAÇÃO</Text>
                <TextInput value={editName} onChangeText={setEditName} style={styles.input} placeholder="Nome" placeholderTextColor="#666" />
                <TextInput value={editUrl} onChangeText={setEditUrl} style={styles.input} placeholder="URL GitHub" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
                <Button title="SALVAR ALTERAÇÕES" onPress={saveMenu} secondary />

                <View style={styles.detailSectionRow}>
                  <Text style={styles.sectionInline}>CHAVES FREE/VIP</Text>
                  <Pressable onPress={() => setKeyModal(true)}><Text style={styles.refreshLink}>＋ GERAR CHAVE</Text></Pressable>
                </View>

                {keysLoading ? <ActivityIndicator style={{ marginVertical: 22 }} /> : keys.length === 0 ? (
                  <Text style={styles.emptyCompact}>Nenhuma chave criada.</Text>
                ) : keys.map((item) => (
                  <View key={item.id} style={styles.sessionCard}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={[styles.badge, item.kind === "VIP" && { color: "#D49CFF" }]}>{item.kind}</Text>
                        <Text style={item.status === "ACTIVE" && item.usable !== false ? styles.active : styles.sessionOff}>
                          {item.status === "ACTIVE" && item.usable !== false ? "ATIVA" : item.status === "REVOKED" ? "REVOGADA" : item.usable === false ? "EXPIRADA" : "SUSPENSA"}
                        </Text>
                      </View>
                      <Text style={styles.sessionTitle}>{item.key_hint}</Text>
                      <Text style={styles.accountMeta}>
                        {item.kind === "FREE" ? `Expira ${formatDate(item.expires_at)}` : "Permanente"}
                        {typeof item.use_count === "number" ? ` • ${item.use_count} uso(s)` : ""}
                        {item.note ? ` • ${item.note}` : ""}
                      </Text>
                    </View>
                    {item.status !== "REVOKED" ? (
                      <View style={{ gap: 6 }}>
                        <Pressable style={styles.revokeButton} onPress={() => keyAction(item, item.status === "ACTIVE" ? "suspend" : "restore")}>
                          <Text style={styles.revokeButtonText}>{item.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"}</Text>
                        </Pressable>
                        {item.kind === "FREE" ? (
                          <>
                            <Pressable style={styles.revokeButton} onPress={() => {
                              setDurationTarget(item);
                              setNewDurationHours("24");
                            }}>
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

                <Button title={selected.status === "ACTIVE" ? "SUSPENDER MENU" : "LIBERAR MENU"} danger={selected.status === "ACTIVE"} secondary={selected.status !== "ACTIVE"} onPress={() => toggleMenu(selected)} />
                <Button title="EXCLUIR MENU" danger onPress={() => {
                  Alert.alert(
                    "Excluir menu",
                    `Excluir ${selected.name}? O loader deixará de funcionar e as chaves/sessões associadas serão invalidadas. O arquivo original no GitHub não será apagado.`,
                    [
                      { text: "Cancelar", style: "cancel" },
                      { text: "Excluir", style: "destructive", onPress: () => deleteMenu(selected) }
                    ]
                  );
                }} />
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
            <Text style={styles.muted}>A nova expiração é calculada pelo relógio do servidor a partir de agora. Sessões antigas desta chave serão encerradas.</Text>
            <TextInput
              value={newDurationHours}
              onChangeText={setNewDurationHours}
              style={styles.input}
              keyboardType="numeric"
              placeholder="Horas"
              placeholderTextColor="#666"
            />
            <Button title="SALVAR NOVA DURAÇÃO" onPress={changeDuration} />
            <Button title="CANCELAR" onPress={() => setDurationTarget(null)} secondary />
          </View>
        </View>
      </Modal>

      <CredentialModal credential={revealedKey} onClose={() => setRevealedKey(null)} />
    </SafeAreaView>
  );
}
