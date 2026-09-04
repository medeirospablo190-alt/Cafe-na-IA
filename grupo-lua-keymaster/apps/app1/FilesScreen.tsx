import { useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Clipboard from "expo-clipboard";
import {
  createLibraryItem,
  deleteLibraryItems,
  getLibraryItem,
  listLibraryItems,
  setLibraryFavorite,
  shareLibraryItem,
  updateLibraryItem,
  type LibraryItem,
  type LibraryItemSummary,
  type LibraryKind
} from "./api";

type LibraryTab = LibraryKind | "PHOTO" | "VIDEO";

const PAGE_SIZE = 60;
const MAX_SELECTION = 500;
const MAX_TEXT_BYTES = 1_000_000;

function utf8ByteLength(value: string) {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) bytes += 1;
    else if (code <= 0x7ff) bytes += 2;
    else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        index += 1;
      } else bytes += 3;
    } else bytes += 3;
  }
  return bytes;
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function bytesLabel(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function tabLabel(tab: LibraryTab) {
  if (tab === "CODE") return "Códigos";
  if (tab === "LOADSTRING") return "Loadstrings";
  if (tab === "PHOTO") return "Fotos";
  return "Vídeos";
}

function kindSingular(kind: LibraryKind) {
  return kind === "CODE" ? "código" : "loadstring";
}

export function FilesScreen({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [tab, setTab] = useState<LibraryTab>("CODE");
  const [items, setItems] = useState<LibraryItemSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [query, setQuery] = useState("");
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [editor, setEditor] = useState<LibraryItem | { id: null; kind: LibraryKind; title: string; content: string } | null>(null);
  const [editorBusy, setEditorBusy] = useState(false);
  const [mutationBusy, setMutationBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const reloadVersion = useRef(0);
  const suppressPressUntil = useRef(0);

  const textTab = tab === "CODE" || tab === "LOADSTRING";
  const selectedItems = useMemo(
    () => items.filter((item) => selectedIds.includes(item.id)),
    [items, selectedIds]
  );
  const selectionMode = selectedIds.length > 0;
  const anySelectedFavorite = selectedItems.some((item) => item.favorite);
  const anySelectedUnfavorite = selectedItems.some((item) => !item.favorite);

  async function reload({ append = false }: { append?: boolean } = {}) {
    const version = ++reloadVersion.current;
    if (!textTab) {
      if (version === reloadVersion.current) {
        setItems([]);
        setTotal(0);
        setHasMore(false);
        setLoading(false);
        setLoadingMore(false);
      }
      return;
    }

    const offset = append ? items.length : 0;
    if (append) {
      setLoadingMore(true);
    } else {
      setLoading(true);
      setLoadingMore(false);
      setMessage(null);
    }

    try {
      const result = await listLibraryItems(sessionToken, deviceToken, {
        kind: tab,
        q: query.trim() || undefined,
        favorite: favoritesOnly ? true : undefined,
        limit: PAGE_SIZE,
        offset
      });
      if (version !== reloadVersion.current) return;

      if (append) {
        setItems((current) => {
          const known = new Set(current.map((item) => item.id));
          return [...current, ...result.items.filter((item) => !known.has(item.id))];
        });
      } else {
        setItems(result.items);
        setSelectedIds((current) => current.filter((id) => result.items.some((item) => item.id === id)));
      }
      setTotal(result.total);
      setHasMore(result.hasMore);
    } catch (error) {
      if (version !== reloadVersion.current) return;
      setMessage(error instanceof Error ? error.message : "Não foi possível carregar os arquivos.");
    } finally {
      if (version === reloadVersion.current) {
        if (append) setLoadingMore(false);
        else setLoading(false);
      }
    }
  }

  useEffect(() => {
    reloadVersion.current += 1;
    setSelectedIds([]);
    setLoadingMore(false);
    if (!textTab) {
      setItems([]);
      setTotal(0);
      setHasMore(false);
      setLoading(false);
      return;
    }
    setLoading(true);
    const timer = setTimeout(() => reload().catch(() => {}), 280);
    return () => {
      clearTimeout(timer);
      reloadVersion.current += 1;
    };
  }, [tab, query, favoritesOnly, sessionToken, deviceToken]);

  function toggleSelection(id: string) {
    if (mutationBusy) return;
    if (!selectedIds.includes(id) && selectedIds.length >= MAX_SELECTION) {
      setMessage(`Você pode selecionar no máximo ${MAX_SELECTION} itens por vez.`);
      return;
    }
    setSelectedIds((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id]);
  }

  function handleLongPress(id: string) {
    suppressPressUntil.current = Date.now() + 650;
    toggleSelection(id);
  }

  function handleItemPress(item: LibraryItemSummary) {
    if (Date.now() < suppressPressUntil.current) return;
    openItem(item).catch(() => {});
  }

  async function openItem(item: LibraryItemSummary) {
    if (selectionMode) {
      toggleSelection(item.id);
      return;
    }
    if (editorBusy || mutationBusy) return;
    setEditorBusy(true);
    try {
      const result = await getLibraryItem(sessionToken, deviceToken, item.id);
      setEditor(result.item);
    } catch (error) {
      Alert.alert("Arquivo indisponível", error instanceof Error ? error.message : "Não foi possível abrir.");
    } finally {
      setEditorBusy(false);
    }
  }

  function createNew() {
    if (!textTab || editorBusy || mutationBusy) return;
    setEditor({ id: null, kind: tab, title: "", content: "" });
  }

  async function saveEditor() {
    if (!editor || editorBusy || mutationBusy) return;
    const title = editor.title.trim();
    if (!title) {
      Alert.alert("Nome obrigatório", `Dê um nome para este ${kindSingular(editor.kind)} antes de salvar.`);
      return;
    }
    if (!editor.content.trim()) {
      Alert.alert("Conteúdo vazio", "Digite ou cole o conteúdo antes de salvar.");
      return;
    }
    const contentBytes = utf8ByteLength(editor.content);
    if (contentBytes > MAX_TEXT_BYTES) {
      Alert.alert(
        "Arquivo muito grande",
        `Este conteúdo tem ${bytesLabel(contentBytes)}. O limite por código/loadstring é ${bytesLabel(MAX_TEXT_BYTES)}.`
      );
      return;
    }
    setEditorBusy(true);
    try {
      if (editor.id) {
        await updateLibraryItem(sessionToken, deviceToken, editor.id, { title, content: editor.content });
      } else {
        await createLibraryItem(sessionToken, deviceToken, { kind: editor.kind, title, content: editor.content });
      }
      setEditor(null);
      await reload();
    } catch (error) {
      Alert.alert("Não foi possível salvar", error instanceof Error ? error.message : "Erro desconhecido.");
    } finally {
      setEditorBusy(false);
    }
  }

  async function copySummary(item: LibraryItemSummary) {
    if (mutationBusy) return;
    try {
      const result = await getLibraryItem(sessionToken, deviceToken, item.id);
      await Clipboard.setStringAsync(result.item.content);
      setMessage(`${item.title} copiado.`);
    } catch (error) {
      Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar.");
    }
  }

  async function toggleFavorite(ids: string[], favorite: boolean) {
    if (mutationBusy || !ids.length) return;
    setMutationBusy(true);
    try {
      await setLibraryFavorite(sessionToken, deviceToken, ids, favorite);
      setSelectedIds([]);
      await reload();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível alterar favoritos.");
    } finally {
      setMutationBusy(false);
    }
  }

  function confirmDelete(ids: string[]) {
    if (mutationBusy || !ids.length) return;
    const count = ids.length;
    Alert.alert(
      count === 1 ? "Excluir arquivo" : `Excluir ${count} arquivos`,
      "A exclusão é permanente: o conteúdo também será removido do servidor e de publicações que dependam dele.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Excluir",
          style: "destructive",
          onPress: async () => {
            if (mutationBusy) return;
            setMutationBusy(true);
            try {
              await deleteLibraryItems(sessionToken, deviceToken, ids);
              setSelectedIds([]);
              await reload();
            } catch (error) {
              Alert.alert("Não foi possível excluir", error instanceof Error ? error.message : "Erro desconhecido.");
            } finally {
              setMutationBusy(false);
            }
          }
        }
      ]
    );
  }

  async function shareOne(item?: LibraryItemSummary) {
    if (!item || mutationBusy) return;
    setMutationBusy(true);
    try {
      await shareLibraryItem(sessionToken, deviceToken, item.id);
      setSelectedIds([]);
      setMessage(`${item.title} foi compartilhado no feed.`);
      await reload();
    } catch (error) {
      Alert.alert("Não foi possível compartilhar", error instanceof Error ? error.message : "Erro desconhecido.");
    } finally {
      setMutationBusy(false);
    }
  }

  const editorBytes = editor ? utf8ByteLength(editor.content) : 0;

  return (
    <View style={local.root}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={local.tabs}>
        {(["CODE", "LOADSTRING", "PHOTO", "VIDEO"] as LibraryTab[]).map((item) => (
          <Pressable
            key={item}
            style={[local.tab, tab === item && local.tabActive, mutationBusy && local.disabled]}
            disabled={mutationBusy}
            onPress={() => setTab(item)}
          >
            <Text style={[local.tabText, tab === item && local.tabTextActive]}>{tabLabel(item)}</Text>
          </Pressable>
        ))}
      </ScrollView>

      {textTab ? (
        <>
          <View style={local.summaryRow}>
            <View style={{ flex: 1 }}>
              <Text style={local.title}>{tabLabel(tab)}</Text>
              <Text style={local.subtitle}>{total} salvo(s) no servidor • {items.length} exibido(s)</Text>
            </View>
            <Pressable
              style={[local.addButton, (editorBusy || mutationBusy) && local.disabled]}
              disabled={editorBusy || mutationBusy}
              onPress={createNew}
            >
              <Text style={local.addIcon}>＋</Text>
            </Pressable>
          </View>

          <View style={local.searchRow}>
            <TextInput
              value={query}
              onChangeText={setQuery}
              placeholder={`Buscar ${tab === "CODE" ? "códigos" : "loadstrings"}...`}
              placeholderTextColor="#67676E"
              style={local.search}
              autoCapitalize="none"
              autoCorrect={false}
              editable={!mutationBusy}
            />
            <Pressable
              style={[local.favoriteFilter, favoritesOnly && local.favoriteFilterActive, mutationBusy && local.disabled]}
              disabled={mutationBusy}
              onPress={() => setFavoritesOnly((value) => !value)}
            >
              <Text style={[local.favoriteIcon, favoritesOnly && local.favoriteIconActive]}>★</Text>
            </Pressable>
          </View>

          {selectionMode ? (
            <View style={local.selectionBar}>
              <View style={{ flex: 1 }}>
                <Text style={local.selectionTitle}>{selectedIds.length} selecionado(s)</Text>
                <Text style={local.selectionHint}>{selectedIds.length > 1 ? "Compartilhar fica disponível apenas com 1 item." : "Escolha uma ação."}</Text>
              </View>
              <Pressable disabled={mutationBusy} onPress={() => setSelectedIds([])}>
                <Text style={local.clearSelection}>✕</Text>
              </Pressable>
            </View>
          ) : null}

          {selectionMode ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={local.bulkActions}>
              {anySelectedUnfavorite ? (
                <Pressable
                  style={[local.bulkButton, mutationBusy && local.disabled]}
                  disabled={mutationBusy}
                  onPress={() => toggleFavorite(selectedIds, true)}
                >
                  <Text style={local.bulkButtonText}>★ FAVORITAR</Text>
                </Pressable>
              ) : null}
              {anySelectedFavorite ? (
                <Pressable
                  style={[local.bulkButton, mutationBusy && local.disabled]}
                  disabled={mutationBusy}
                  onPress={() => toggleFavorite(selectedIds, false)}
                >
                  <Text style={local.bulkButtonText}>☆ DESFAVORITAR</Text>
                </Pressable>
              ) : null}
              <Pressable
                style={[local.bulkButton, local.bulkDanger, mutationBusy && local.disabled]}
                disabled={mutationBusy}
                onPress={() => confirmDelete(selectedIds)}
              >
                <Text style={local.bulkDangerText}>EXCLUIR</Text>
              </Pressable>
              {selectedIds.length === 1 && selectedItems[0] ? (
                <Pressable
                  style={[local.bulkButton, mutationBusy && local.disabled]}
                  disabled={mutationBusy}
                  onPress={() => shareOne(selectedItems[0])}
                >
                  <Text style={local.bulkButtonText}>{mutationBusy ? "AGUARDE..." : "COMPARTILHAR"}</Text>
                </Pressable>
              ) : null}
            </ScrollView>
          ) : null}

          {message ? <Text style={local.message}>{message}</Text> : null}
          {loading || editorBusy ? <ActivityIndicator style={{ marginVertical: 28 }} /> : null}
          {!loading && !editorBusy && items.length === 0 ? (
            <View style={local.emptyCard}>
              <Text style={local.emptyIcon}>{tab === "CODE" ? "⌘" : "↗"}</Text>
              <Text style={local.emptyTitle}>Nenhum {tab === "CODE" ? "código" : "loadstring"} aqui</Text>
              <Text style={local.emptyText}>Toque no + para criar e salvar o primeiro item no servidor.</Text>
            </View>
          ) : null}

          {!loading && !editorBusy ? items.map((item) => {
            const selected = selectedIds.includes(item.id);
            return (
              <Pressable
                key={item.id}
                style={[local.itemCard, selected && local.itemSelected, mutationBusy && local.disabled]}
                disabled={mutationBusy}
                onPress={() => handleItemPress(item)}
                onLongPress={() => handleLongPress(item.id)}
                delayLongPress={320}
              >
                <View style={local.itemHeader}>
                  <View style={[local.fileIcon, item.kind === "LOADSTRING" && local.fileIconLoad]}>
                    <Text style={local.fileIconText}>{item.kind === "CODE" ? "</>" : "LS"}</Text>
                  </View>
                  <View style={{ flex: 1 }}>
                    <View style={local.nameRow}>
                      <Text numberOfLines={1} style={local.itemTitle}>{item.title}</Text>
                      {item.favorite ? <Text style={local.star}>★</Text> : null}
                    </View>
                    <Text style={local.meta}>{bytesLabel(item.contentBytes)} • editado {formatDate(item.updatedAt)}</Text>
                  </View>
                  {selected ? <View style={local.check}><Text style={local.checkText}>✓</Text></View> : null}
                </View>

                <Text numberOfLines={3} style={local.preview}>{item.preview || "Sem prévia"}</Text>

                {!selectionMode ? (
                  <View style={local.actions}>
                    <Pressable
                      style={local.action}
                      onPress={(event) => { event.stopPropagation(); openItem(item); }}
                    >
                      <Text style={local.actionText}>EDITAR</Text>
                    </Pressable>
                    <Pressable
                      style={local.action}
                      onPress={(event) => { event.stopPropagation(); copySummary(item); }}
                    >
                      <Text style={local.actionText}>COPIAR</Text>
                    </Pressable>
                    <Pressable
                      style={local.action}
                      onPress={(event) => { event.stopPropagation(); toggleFavorite([item.id], !item.favorite); }}
                    >
                      <Text style={local.actionText}>{item.favorite ? "☆" : "★"}</Text>
                    </Pressable>
                    <Pressable
                      style={local.action}
                      onPress={(event) => { event.stopPropagation(); shareOne(item); }}
                    >
                      <Text style={local.actionText}>FEED</Text>
                    </Pressable>
                  </View>
                ) : null}
              </Pressable>
            );
          }) : null}

          {!loading && !editorBusy && hasMore ? (
            <Pressable
              style={[local.loadMoreButton, (loadingMore || mutationBusy) && local.disabled]}
              disabled={loadingMore || mutationBusy}
              onPress={() => reload({ append: true })}
            >
              {loadingMore ? <ActivityIndicator size="small" /> : <Text style={local.loadMoreText}>CARREGAR MAIS</Text>}
            </Pressable>
          ) : null}
        </>
      ) : (
        <View style={local.mediaPlaceholder}>
          <View style={local.mediaPlus}><Text style={local.mediaPlusText}>＋</Text></View>
          <Text style={local.emptyTitle}>{tabLabel(tab)}</Text>
          <Text style={local.emptyText}>Esta aba já está reservada. O primeiro quadrado será o + para enviar mídia ao servidor.</Text>
        </View>
      )}

      <Modal visible={Boolean(editor)} transparent animationType="slide" onRequestClose={() => !editorBusy && setEditor(null)}>
        <KeyboardAvoidingView style={local.modalKeyboard} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <View style={local.modalBackdrop}>
            <View style={local.editorModal}>
              {editor ? (
                <>
                  <View style={local.editorHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={local.editorEyebrow}>{editor.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
                      <Text style={local.editorTitle}>{editor.id ? "Editar arquivo" : "Novo arquivo"}</Text>
                    </View>
                    <Pressable disabled={editorBusy} onPress={() => setEditor(null)}>
                      <Text style={local.close}>✕</Text>
                    </Pressable>
                  </View>

                  <TextInput
                    value={editor.title}
                    onChangeText={(title) => setEditor({ ...editor, title })}
                    placeholder="Nome do arquivo"
                    placeholderTextColor="#626268"
                    style={local.nameInput}
                    maxLength={120}
                    editable={!editorBusy}
                  />
                  <TextInput
                    value={editor.content}
                    onChangeText={(content) => setEditor({ ...editor, content })}
                    placeholder="Digite ou cole o conteúdo aqui..."
                    placeholderTextColor="#55555C"
                    style={local.codeInput}
                    multiline
                    textAlignVertical="top"
                    autoCapitalize="none"
                    autoCorrect={false}
                    editable={!editorBusy}
                  />
                  <Text style={[local.editorSize, editorBytes > MAX_TEXT_BYTES && local.editorSizeDanger]}>
                    {bytesLabel(editorBytes)} / {bytesLabel(MAX_TEXT_BYTES)}
                  </Text>

                  <View style={local.editorActions}>
                    {editor.content ? (
                      <Pressable
                        style={[local.secondaryButton, editorBusy && local.disabled]}
                        disabled={editorBusy}
                        onPress={() => Clipboard.setStringAsync(editor.content)}
                      >
                        <Text style={local.secondaryButtonText}>COPIAR</Text>
                      </Pressable>
                    ) : null}
                    <Pressable style={[local.saveButton, (editorBusy || editorBytes > MAX_TEXT_BYTES) && local.disabled]} disabled={editorBusy || editorBytes > MAX_TEXT_BYTES} onPress={saveEditor}>
                      <Text style={local.saveButtonText}>{editorBusy ? "SALVANDO..." : "SALVAR NO SERVIDOR"}</Text>
                    </Pressable>
                  </View>
                </>
              ) : null}
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const local = StyleSheet.create({
  root: { flex: 1 },
  disabled: { opacity: 0.5 },
  tabs: { gap: 8, paddingVertical: 4, paddingRight: 18 },
  tab: { borderWidth: 1, borderColor: "#26262C", backgroundColor: "#0C0C0F", borderRadius: 999, paddingHorizontal: 15, paddingVertical: 9 },
  tabActive: { borderColor: "#7B4CA5", backgroundColor: "#1A1024" },
  tabText: { color: "#86868D", fontSize: 11, fontWeight: "800" },
  tabTextActive: { color: "#FFFFFF" },
  summaryRow: { flexDirection: "row", alignItems: "center", marginTop: 18 },
  title: { color: "#FFFFFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "#74747C", fontSize: 11, marginTop: 3 },
  addButton: { width: 48, height: 48, borderRadius: 15, borderWidth: 1, borderColor: "#7542A4", backgroundColor: "#1A1024", alignItems: "center", justifyContent: "center" },
  addIcon: { color: "#C792FF", fontSize: 28, lineHeight: 30 },
  searchRow: { flexDirection: "row", gap: 9, marginTop: 14 },
  search: { flex: 1, minHeight: 48, borderRadius: 14, borderWidth: 1, borderColor: "#25252B", backgroundColor: "#0C0C0F", color: "#FFFFFF", paddingHorizontal: 14, fontSize: 14 },
  favoriteFilter: { width: 48, minHeight: 48, borderRadius: 14, borderWidth: 1, borderColor: "#2C2C31", backgroundColor: "#0C0C0F", alignItems: "center", justifyContent: "center" },
  favoriteFilterActive: { borderColor: "#8D6820", backgroundColor: "#1A1408" },
  favoriteIcon: { color: "#6F6F76", fontSize: 18 },
  favoriteIconActive: { color: "#FFD35A" },
  selectionBar: { flexDirection: "row", alignItems: "center", marginTop: 12, padding: 13, borderRadius: 14, borderWidth: 1, borderColor: "#3C2A4E", backgroundColor: "#110B17" },
  selectionTitle: { color: "#FFFFFF", fontWeight: "900", fontSize: 12 },
  selectionHint: { color: "#8C8095", fontSize: 10, marginTop: 3 },
  clearSelection: { color: "#B8A7C8", fontSize: 20, padding: 5 },
  bulkActions: { gap: 8, paddingVertical: 10, paddingRight: 14 },
  bulkButton: { borderRadius: 10, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#101014", paddingHorizontal: 13, paddingVertical: 10 },
  bulkButtonText: { color: "#E8E8EC", fontSize: 9, fontWeight: "900" },
  bulkDanger: { borderColor: "#552326", backgroundColor: "#16090A" },
  bulkDangerText: { color: "#FF6258", fontSize: 9, fontWeight: "900" },
  message: { color: "#9E87B4", fontSize: 11, marginTop: 10 },
  emptyCard: { marginTop: 18, borderWidth: 1, borderColor: "#222228", borderRadius: 18, backgroundColor: "#09090C", padding: 28, alignItems: "center" },
  emptyIcon: { color: "#8856B5", fontSize: 28, fontWeight: "900" },
  emptyTitle: { color: "#FFFFFF", fontSize: 16, fontWeight: "900", marginTop: 10 },
  emptyText: { color: "#777780", fontSize: 12, lineHeight: 18, textAlign: "center", marginTop: 6 },
  itemCard: { marginTop: 10, borderRadius: 17, borderWidth: 1, borderColor: "#25252B", backgroundColor: "#09090C", padding: 14 },
  itemSelected: { borderColor: "#8856B5", backgroundColor: "#120C18" },
  itemHeader: { flexDirection: "row", alignItems: "center", gap: 11 },
  fileIcon: { width: 42, height: 42, borderRadius: 12, borderWidth: 1, borderColor: "#44305A", backgroundColor: "#160F1E", alignItems: "center", justifyContent: "center" },
  fileIconLoad: { borderColor: "#234651", backgroundColor: "#09171B" },
  fileIconText: { color: "#C995FF", fontWeight: "900", fontSize: 11 },
  nameRow: { flexDirection: "row", alignItems: "center", gap: 7 },
  itemTitle: { color: "#F3F3F5", fontWeight: "900", fontSize: 14, flexShrink: 1 },
  star: { color: "#FFD35A", fontSize: 13 },
  meta: { color: "#686870", fontSize: 9, marginTop: 4 },
  check: { width: 25, height: 25, borderRadius: 99, backgroundColor: "#8653B4", alignItems: "center", justifyContent: "center" },
  checkText: { color: "#FFFFFF", fontSize: 12, fontWeight: "900" },
  preview: { color: "#8D8D94", fontFamily: "monospace", fontSize: 10, lineHeight: 15, marginTop: 12 },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 12 },
  action: { flexGrow: 1, minWidth: 65, borderRadius: 9, borderWidth: 1, borderColor: "#2A2A30", paddingVertical: 8, alignItems: "center" },
  actionText: { color: "#CFCFD3", fontWeight: "900", fontSize: 8 },
  loadMoreButton: { minHeight: 48, marginTop: 14, borderRadius: 13, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#0D0D11", alignItems: "center", justifyContent: "center" },
  loadMoreText: { color: "#D7D7DC", fontSize: 10, fontWeight: "900", letterSpacing: 0.5 },
  mediaPlaceholder: { marginTop: 22, minHeight: 260, borderWidth: 1, borderColor: "#25252B", borderRadius: 20, backgroundColor: "#09090C", alignItems: "center", justifyContent: "center", padding: 28 },
  mediaPlus: { width: 96, height: 96, borderRadius: 18, borderWidth: 1, borderStyle: "dashed", borderColor: "#76509A", backgroundColor: "#110B17", alignItems: "center", justifyContent: "center" },
  mediaPlusText: { color: "#C792FF", fontSize: 40 },
  modalKeyboard: { flex: 1 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.92)", justifyContent: "flex-end" },
  editorModal: { height: "92%", backgroundColor: "#070709", borderTopLeftRadius: 22, borderTopRightRadius: 22, borderWidth: 1, borderColor: "#2B2B30", padding: 16 },
  editorHeader: { flexDirection: "row", alignItems: "flex-start", paddingBottom: 12 },
  editorEyebrow: { color: "#8D5EB5", fontSize: 9, fontWeight: "900", letterSpacing: 1.4 },
  editorTitle: { color: "#FFFFFF", fontSize: 21, fontWeight: "900", marginTop: 4 },
  close: { color: "#A7A7AD", fontSize: 22, padding: 5 },
  nameInput: { minHeight: 50, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#0E0E12", color: "#FFFFFF", paddingHorizontal: 14, fontSize: 15 },
  codeInput: { flex: 1, minHeight: 220, marginTop: 10, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#050507", color: "#DADADF", padding: 14, fontFamily: "monospace", fontSize: 12, lineHeight: 18 },
  editorSize: { color: "#76767E", fontSize: 10, textAlign: "right", marginTop: 6 },
  editorSizeDanger: { color: "#FF6258", fontWeight: "900" },
  editorActions: { flexDirection: "row", gap: 9, marginTop: 10 },
  secondaryButton: { minHeight: 48, borderRadius: 13, borderWidth: 1, borderColor: "#303036", paddingHorizontal: 18, alignItems: "center", justifyContent: "center" },
  secondaryButtonText: { color: "#E0E0E4", fontSize: 10, fontWeight: "900" },
  saveButton: { flex: 1, minHeight: 48, borderRadius: 13, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 14 },
  saveButtonText: { color: "#050505", fontSize: 10, fontWeight: "900" }
});
