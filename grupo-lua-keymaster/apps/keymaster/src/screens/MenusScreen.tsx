import { useEffect, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Modal,
  Pressable,
  SafeAreaView,
  Text,
  TextInput,
  View
} from "react-native";
import { StatusBar } from "expo-status-bar";
import * as Clipboard from "expo-clipboard";
import {
  type ManagedMenu,
  createManagedMenu,
  listManagedMenus,
  setManagedMenuState,
  updateManagedMenu
} from "../api";
import { BottomNav } from "../components/BottomNav";
import { Button, Header } from "../components/Common";
import { buildMenuLoader } from "../menuLoader";
import { styles } from "../styles";

type StatusFilter = "ALL" | "ACTIVE" | "SUSPENDED";

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
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const [sourceUrl, setSourceUrl] = useState("");
  const [selected, setSelected] = useState<ManagedMenu | null>(null);
  const [editName, setEditName] = useState("");
  const [editUrl, setEditUrl] = useState("");

  async function refresh() {
    setLoading(true);
    try {
      const result = await listManagedMenus(session, {
        q: query.trim() || undefined,
        status: statusFilter === "ALL" ? undefined : statusFilter
      });
      setMenus(result.menus);
      if (selected) {
        const fresh = result.menus.find((item) => item.id === selected.id) || null;
        setSelected(fresh);
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

  function open(menu: ManagedMenu) {
    setSelected(menu);
    setEditName(menu.name);
    setEditUrl(menu.source_url);
  }

  async function copyLoader(menu: ManagedMenu) {
    const loader = buildMenuLoader(menu.public_id);
    if (!loader) {
      Alert.alert("Menu inválido", "O ID público deste menu não pôde ser convertido em loadstring.");
      return;
    }

    try {
      await Clipboard.setStringAsync(loader);
      Alert.alert("Loadstring copiado", `O loader de ${menu.name} foi copiado.`);
    } catch (error) {
      Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar o loadstring.");
    }
  }

  async function create() {
    try {
      const result = await createManagedMenu(session, name, sourceUrl);
      setName("");
      setSourceUrl("");
      setCreateOpen(false);
      await refresh();
      open(result.menu);
      Alert.alert(
        "Menu cadastrado",
        "O menu foi criado com o login-base oficial. Use “COPIAR LOADSTRING” para obter o loader final."
      );
    } catch (error) {
      Alert.alert("Não foi possível cadastrar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function save() {
    if (!selected) return;
    try {
      const result = await updateManagedMenu(session, selected.id, { name: editName, sourceUrl: editUrl });
      setSelected(result.menu);
      setEditName(result.menu.name);
      setEditUrl(result.menu.source_url);
      await refresh();
      Alert.alert("Menu atualizado", "Nome e origem foram salvos.");
    } catch (error) {
      Alert.alert("Falha ao editar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function toggle(menu: ManagedMenu) {
    try {
      const result = await setManagedMenuState(session, menu.id, menu.status === "ACTIVE" ? "suspend" : "restore");
      if (selected?.id === menu.id) setSelected(result.menu);
      await refresh();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <View style={styles.screenBody}>
          <Header title="MENUS" onBack={onHome} />
          <View style={styles.listHeaderCompact}>
            <View style={{ flex: 1 }}>
              <Text style={styles.screenTitle}>Menus</Text>
              <Text style={styles.muted}>Cadastre e suspenda menus. FREE/VIP agora são administradas somente no App 1.</Text>
            </View>
            <Pressable style={styles.addButton} onPress={() => setCreateOpen(true)}><Text style={styles.add}>＋</Text></Pressable>
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

          <View style={styles.filterRow}>
            {(["ALL", "ACTIVE", "SUSPENDED"] as StatusFilter[]).map((item) => (
              <Pressable key={item} style={[styles.filterChip, statusFilter === item && styles.filterChipActive]} onPress={() => setStatusFilter(item)}>
                <Text style={[styles.filterChipText, statusFilter === item && styles.filterChipTextActive]}>
                  {item === "ALL" ? "TODOS" : item === "ACTIVE" ? "ATIVOS" : "SUSPENSOS"}
                </Text>
              </Pressable>
            ))}
          </View>

          {loading ? <ActivityIndicator style={{ marginTop: 30 }} /> : (
            <FlatList
              data={menus}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.accountList}
              ListEmptyComponent={<Text style={styles.empty}>Nenhum menu cadastrado.</Text>}
              renderItem={({ item }) => (
                <View style={styles.accountCard}>
                  <Pressable onPress={() => open(item)} style={styles.accountTop}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={styles.cardTitle}>{item.name}</Text>
                        <Text style={styles.badge}>{item.public_id}</Text>
                      </View>
                      <Text style={styles.accountMeta} numberOfLines={1}>{item.source_url}</Text>
                      <Text style={styles.accountMeta}>Chaves: gerenciadas no App 1</Text>
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : styles.suspended}>{item.status === "ACTIVE" ? "ATIVO" : "SUSPENSO"}</Text>
                  </Pressable>

                  <View style={styles.rowGap}>
                    <Pressable style={styles.smallAction} onPress={() => copyLoader(item)}>
                      <Text style={styles.smallActionText}>COPIAR LOADSTRING</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => open(item)}>
                      <Text style={styles.smallActionText}>EDITAR</Text>
                    </Pressable>
                    <Pressable style={[styles.smallAction, item.status === "ACTIVE" && styles.smallDanger]} onPress={() => toggle(item)}>
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

      <Modal visible={createOpen} transparent animationType="fade" onRequestClose={() => setCreateOpen(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Cadastrar novo menu</Text>
            <Text style={styles.muted}>Cadastre o arquivo .lua. As chaves deste menu serão criadas pelo App 1.</Text>
            <TextInput value={name} onChangeText={setName} style={styles.input} placeholder="Nome do menu" placeholderTextColor="#666" />
            <TextInput value={sourceUrl} onChangeText={setSourceUrl} style={styles.input} placeholder="https://github.com/.../Menu.lua" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
            <Button title="CADASTRAR MENU" onPress={create} disabled={name.trim().length < 2 || !sourceUrl.trim()} />
            <Button title="FECHAR" onPress={() => setCreateOpen(false)} secondary />
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(selected)} transparent animationType="slide" onRequestClose={() => setSelected(null)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalBox, styles.detailModal]}>
            {selected ? (
              <View>
                <View style={styles.detailHeader}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.cardTitle}>{selected.name}</Text>
                    <Text style={styles.accountMeta}>{selected.public_id} • {selected.status}</Text>
                  </View>
                  <Pressable onPress={() => setSelected(null)}><Text style={styles.closeText}>✕</Text></Pressable>
                </View>

                <Text style={styles.section}>CONFIGURAÇÃO</Text>
                <TextInput value={editName} onChangeText={setEditName} style={styles.input} placeholder="Nome" placeholderTextColor="#666" />
                <TextInput value={editUrl} onChangeText={setEditUrl} style={styles.input} placeholder="URL GitHub" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
                <Button title="SALVAR ALTERAÇÕES" onPress={save} secondary />
                <Button title="COPIAR LOADSTRING" onPress={() => copyLoader(selected)} secondary />
                <Button title={selected.status === "ACTIVE" ? "SUSPENDER MENU" : "LIBERAR MENU"} onPress={() => toggle(selected)} secondary />

                <Text style={styles.muted}>FREE, VIP, validade, liberação após 24h e vínculo de aparelho ficam exclusivamente no App 1.</Text>
              </View>
            ) : null}
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}
