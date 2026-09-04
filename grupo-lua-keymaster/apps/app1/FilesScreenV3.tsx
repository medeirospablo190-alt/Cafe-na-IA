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
  updateLibraryItem,
  type LibraryItem,
  type LibraryItemSummary,
  type LibraryKind
} from "./api";
import { shareLibraryItemWithComment } from "./library-social-api";

type LibraryTab = LibraryKind | "PHOTO" | "VIDEO";
type EditorState = LibraryItem | { id: null; kind: LibraryKind; title: string; content: string };

const PAGE_SIZE = 60;
const MAX_SELECTION = 500;
const MAX_CODE_BYTES = 1_000_000;
const MAX_LOADSTRING_CHARS = 32_768;
const MAX_SHARE_COMMENT_CHARS = 500;

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

function codePointLength(value: string) {
  return Array.from(value).length;
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
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [editorBusy, setEditorBusy] = useState(false);
  const [mutationBusy, setMutationBusy] = useState(false);
  const [shareTarget, setShareTarget] = useState<LibraryItemSummary | null>(null);
  const [shareComment, setShareComment] = useState("");
  const [shareFavorite, setShareFavorite] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const reloadVersion = useRef(0);
  const suppressPressUntil = useRef(0);
  const mutationLock = useRef(false);
  const editorOpenLock = useRef(false);
  const editorSaveLock = useRef(false);

  const textTab = tab === "CODE" || tab === "LOADSTRING";
  const selectionMode = selectedIds.length > 0;
  const selectedItems = useMemo(
    () => items.filter((item) => selectedIds.includes(item.id)),
    [items, selectedIds]
  );
  const anySelectedFavorite = selectedItems.some((item) => item.favorite);
  const anySelectedUnfavorite = selectedItems.some((item) => !item.favorite);
  const editorBytes = editor ? utf8ByteLength(editor.content) : 0;
  const editorChars = editor ? codePointLength(editor.content) : 0;
  const editorTooLarge = Boolean(editor && (
    editor.kind === "LOADSTRING"
      ? editorChars > MAX_LOADSTRING_CHARS
      : editorBytes > MAX_CODE_BYTES
  ));
  const shareCommentChars = codePointLength(shareComment);

  function beginMutation() {
    if (mutationLock.current) return false;
    mutationLock.current = true;
    setMutationBusy(true);
    return true;
  }

  function endMutation() {
    mutationLock.current = false;
    setMutationBusy(false);
  }

  async function reload({ append = false, preserveMessage = false }: {
    append?: boolean;
    preserveMessage?: boolean;
  } = {}) {
    const version = ++reloadVersion.current;
    if (!textTab) {
      if (version === reloadVersion.current) {
        setItems([]);
        setTotal(0);
        setHasMore(false);
        setLoading(false);
        setLoadingMore(false);
      }
      return true;
    }

    const offset = append ? items.length : 0;
    if (append) {
      setLoadingMore(true);
    } else {
      setLoading(true);
      setLoadingMore(false);
      if (!preserveMessage) setMessage(null);
    }

    try {
      const result = await listLibraryItems(sessionToken, deviceToken, {
        kind: tab,
        q: query.trim() || undefined,
        favorite: favoritesOnly ? true : undefined,
        limit: PAGE_SIZE,
        offset
      });
      if (version !== reloadVersion.current) return false;

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
      return true;
    } catch (error) {
      if (version !== reloadVersion.current) return false;
      setMessage(error instanceof Error ? error.message : "Não foi possível carregar os arquivos.");
      return false;
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
    setMessage(null);
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
    if (mutationLock.current) return;
    if (!selectedIds.includes(id) && selectedIds.length >= MAX_SELECTION) {
      setMessage(`Você pode selecionar no máximo ${MAX_SELECTION} itens por vez.`);
      return;
    }
    setSelectedIds((current) => current.includes(id)
      ? current.filter((value) => value !== id)
      : [...current, id]
    );
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
    if (editorOpenLock.current || editorSaveLock.current || mutationLock.current) return;
    editorOpenLock.current = true;
    setEditorBusy(true);
    try {
      const result = await getLibraryItem(sessionToken, deviceToken, item.id);
      setEditor(result.item);
    } catch (error) {
      Alert.alert("Arquivo indisponível", error instanceof Error ? error.message : "Não foi possível abrir.");
    } finally {
      editorOpenLock.current = false;
      setEditorBusy(false);
    }
  }

  function createNew() {
    if (!textTab || editorOpenLock.current || editorSaveLock.current || mutationLock.current) return;
    setEditor({ id: null, kind: tab as LibraryKind, title: "", content: "" });
  }

  function setEditorContent(content: string) {
    if (!editor) return;
    const bounded = editor.kind === "LOADSTRING"
      ? Array.from(content).slice(0, MAX_LOADSTRING_CHARS).join("")
      : content;
    setEditor({ ...editor, content: bounded });
  }

  async function saveEditor() {
    if (!editor || editorSaveLock.current || editorOpenLock.current || mutationLock.current) return;
    const title = editor.title.trim();
    if (!title) {
      Alert.alert("Nome obrigatório", `Dê um nome para este ${kindSingular(editor.kind)} antes de salvar.`);
      return;
    }
    if (!editor.content.trim()) {
      Alert.alert("Conteúdo vazio", "Digite ou cole o conteúdo antes de salvar.");
      return;
    }
    if (editorTooLarge) {
      Alert.alert(
        "Conteúdo muito grande",
        editor.kind === "LOADSTRING"
          ? `O limite é ${MAX_LOADSTRING_CHARS.toLocaleString("pt-BR")} caracteres por loadstring.`
          : `O limite é ${bytesLabel(MAX_CODE_BYTES)} por código.`
      );
      return;
    }

    editorSaveLock.current = true;
    setEditorBusy(true);
    try {
      if (editor.id) {
        await updateLibraryItem(sessionToken, deviceToken, editor.id, { title, content: editor.content });
      } else {
        await createLibraryItem(sessionToken, deviceToken, { kind: editor.kind, title, content: editor.content });
      }
      const savedTitle = title;
      setEditor(null);
      const refreshed = await reload({ preserveMessage: true });
      if (refreshed) setMessage(`${savedTitle} salvo no servidor.`);
    } catch (error) {
      Alert.alert("Não foi possível salvar", error instanceof Error ? error.message : "Erro desconhecido.");
    } finally {
      editorSaveLock.current = false;
      setEditorBusy(false);
    }
  }

  async function copySummary(item: LibraryItemSummary) {
    if (mutationLock.current) return;
    try {
      const result = await getLibraryItem(sessionToken, deviceToken, item.id);
      await Clipboard.setStringAsync(result.item.content);
      setMessage(`${item.title} copiado.`);
    } catch (error) {
      Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar.");
    }
  }

  async function toggleFavorite(ids: string[], favorite: boolean) {
    if (!ids.length || !beginMutation()) return;
    try {
      await setLibraryFavorite(sessionToken, deviceToken, ids, favorite);
      const idSet = new Set(ids);
      setItems((current) => current.map((item) => idSet.has(item.id) ? { ...item, favorite } : item));
      setSelectedIds([]);
      const refreshed = await reload({ preserveMessage: true });
      if (refreshed) setMessage(favorite ? "Adicionado aos favoritos." : "Removido dos favoritos.");
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível alterar favoritos.");
    } finally {
      endMutation();
    }
  }

  function confirmDelete(ids: string[]) {
    if (mutationLock.current || !ids.length) return;
    const count = ids.length;
    Alert.alert(
      count === 1 ? "Excluir arquivo" : `Excluir ${count} arquivos`,
      "A exclusão é permanente. O conteúdo será removido do servidor e publicações do Feed ligadas a ele também serão apagadas.",
      [
        { text: "Não", style: "cancel" },
        {
          text: "Sim, excluir",
          style: "destructive",
          onPress: async () => {
            if (!beginMutation()) return;
            try {
              await deleteLibraryItems(sessionToken, deviceToken, ids);
              const idSet = new Set(ids);
              setItems((current) => current.filter((item) => !idSet.has(item.id)));
              setTotal((current) => Math.max(0, current - ids.length));
              setSelectedIds([]);
              const refreshed = await reload({ preserveMessage: true });
              if (refreshed) setMessage(count === 1 ? "Arquivo excluído." : `${count} arquivos excluídos.`);
            } catch (error) {
              Alert.alert("Não foi possível excluir", error instanceof Error ? error.message : "Erro desconhecido.");
            } finally {
              endMutation();
            }
          }
        }
      ]
    );
  }

  function openShare(item?: LibraryItemSummary) {
    if (!item || mutationLock.current) return;
    setShareTarget(item);
    setShareComment("");
    setShareFavorite(item.favorite);
  }

  function closeShare() {
    if (mutationLock.current) return;
    setShareTarget(null);
    setShareComment("");
    setShareFavorite(false);
  }

  async function submitShare() {
    if (!shareTarget || !beginMutation()) return;
    try {
      const result = await shareLibraryItemWithComment(
        sessionToken,
        deviceToken,
        shareTarget.id,
        shareComment.trim(),
        shareFavorite
      );
      const title = shareTarget.title;
      setItems((current) => current.map((item) => item.id === shareTarget.id
        ? { ...item, favorite: result.favorite, sharedCount: item.sharedCount + 1 }
        : item
      ));
      setShareTarget(null);
      setShareComment("");
      setShareFavorite(false);
      setSelectedIds([]);
      const refreshed = await reload({ preserveMessage: true });
      if (refreshed) setMessage(`${title} foi compartilhado no Feed.`);
    } catch (error) {
      Alert.alert("Não foi possível compartilhar", error instanceof Error ? error.message : "Erro desconhecido.");
    } finally {
      endMutation();
    }
  }

  function setBoundedShareComment(value: string) {
    setShareComment(Array.from(value).slice(0, MAX_SHARE_COMMENT_CHARS).join(""));
  }

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
              accessibilityLabel={`Adicionar ${tab === "CODE" ? "código" : "loadstring"}`}
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
              accessibilityLabel={favoritesOnly ? "Mostrar todos os arquivos" : "Mostrar somente favoritos"}
            >
              <Text style={[local.favoriteIcon, favoritesOnly && local.favoriteIconActive]}>
                {favoritesOnly ? "★" : "☆"}
              </Text>
            </Pressable>
          </View>

          {selectionMode ? (
            <>
              <View style={local.selectionBar}>
                <View style={{ flex: 1 }}>
                  <Text style={local.selectionTitle}>{selectedIds.length} selecionado(s)</Text>
                  <Text style={local.selectionHint}>{selectedIds.length === 1 ? "Escolha uma ação." : "Compartilhar aceita apenas um item por vez."}</Text>
                </View>
                <Pressable disabled={mutationBusy} onPress={() => setSelectedIds([])} accessibilityLabel="Cancelar seleção">
                  <Text style={local.clearSelection}>✕</Text>
                </Pressable>
              </View>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={local.bulkActions}>
                {anySelectedUnfavorite ? (
                  <Pressable style={local.bulkButton} disabled={mutationBusy} onPress={() => toggleFavorite(selectedIds, true)}>
                    <Text style={local.bulkButtonText}>★ FAVORITAR</Text>
                  </Pressable>
                ) : null}
                {anySelectedFavorite ? (
                  <Pressable style={local.bulkButton} disabled={mutationBusy} onPress={() => toggleFavorite(selectedIds, false)}>
                    <Text style={local.bulkButtonText}>☆ DESFAVORITAR</Text>
                  </Pressable>
                ) : null}
                <Pressable style={[local.bulkButton, local.bulkDanger]} disabled={mutationBusy} onPress={() => confirmDelete(selectedIds)}>
                  <Text style={local.bulkDangerText}>EXCLUIR</Text>
                </Pressable>
                {selectedIds.length === 1 && selectedItems[0] ? (
                  <Pressable style={local.bulkButton} disabled={mutationBusy} onPress={() => openShare(selectedItems[0])}>
                    <Text style={local.bulkButtonText}>↗ COMPARTILHAR</Text>
                  </Pressable>
                ) : null}
              </ScrollView>
            </>
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
                    <Text numberOfLines={1} style={local.itemTitle}>{item.title}</Text>
                    <Text style={local.meta}>{bytesLabel(item.contentBytes)} • editado {formatDate(item.updatedAt)}</Text>
                  </View>

                  {selectionMode ? (
                    selected ? <View style={local.check}><Text style={local.checkText}>✓</Text></View> : null
                  ) : (
                    <View style={local.cardTools}>
                      <Pressable
                        style={[local.headerTool, item.favorite && local.headerToolFavorite]}
                        onPress={(event) => {
                          event.stopPropagation();
                          toggleFavorite([item.id], !item.favorite);
                        }}
                        accessibilityLabel={item.favorite ? "Remover dos favoritos" : "Adicionar aos favoritos"}
                      >
                        <Text style={[local.headerStar, item.favorite && local.headerStarActive]}>{item.favorite ? "★" : "☆"}</Text>
                      </Pressable>
                      <Pressable
                        style={[local.headerTool, local.headerTrash]}
                        onPress={(event) => {
                          event.stopPropagation();
                          confirmDelete([item.id]);
                        }}
                        accessibilityLabel={`Excluir ${item.title}`}
                      >
                        <Text style={local.trashIcon}>🗑</Text>
                      </Pressable>
                    </View>
                  )}
                </View>

                <Text numberOfLines={3} style={local.preview}>{item.preview || "Sem prévia"}</Text>

                {!selectionMode ? (
                  <View style={local.actions}>
                    <Pressable style={local.action} onPress={(event) => { event.stopPropagation(); openItem(item); }}>
                      <Text style={local.actionText}>EDITAR</Text>
                    </Pressable>
                    <Pressable style={local.action} onPress={(event) => { event.stopPropagation(); copySummary(item); }}>
                      <Text style={local.actionText}>COPIAR</Text>
                    </Pressable>
                    <Pressable
                      style={local.shareAction}
                      onPress={(event) => { event.stopPropagation(); openShare(item); }}
                      accessibilityLabel="Compartilhar no Feed"
                    >
                      <Text style={local.shareActionIcon}>↗</Text>
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
          <Text style={local.emptyText}>Esta aba está reservada para a próxima etapa de mídia.</Text>
        </View>
      )}

      <Modal visible={Boolean(editor)} transparent animationType="slide" onRequestClose={() => !editorBusy && setEditor(null)}>
        <KeyboardAvoidingView style={local.modalKeyboard} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <View style={local.modalBackdrop}>
            <View style={[local.editorModal, editor?.kind === "LOADSTRING" && local.loadstringEditorModal]}>
              {editor ? (
                <>
                  <View style={local.editorHeader}>
                    <View style={{ flex: 1 }}>
                      <Text style={local.editorEyebrow}>{editor.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
                      <Text style={local.editorTitle}>{editor.id ? "Editar arquivo" : `Novo ${kindSingular(editor.kind)}`}</Text>
                    </View>
                    <Pressable disabled={editorBusy} onPress={() => setEditor(null)} accessibilityLabel="Fechar editor">
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
                    onChangeText={setEditorContent}
                    placeholder={editor.kind === "LOADSTRING" ? "Cole a loadstring aqui..." : "Digite ou cole o código aqui..."}
                    placeholderTextColor="#55555C"
                    style={[local.codeInput, editor.kind === "LOADSTRING" && local.loadstringInput]}
                    multiline
                    scrollEnabled
                    textAlignVertical="top"
                    autoCapitalize="none"
                    autoCorrect={false}
                    editable={!editorBusy}
                  />
                  <Text style={[local.editorSize, editorTooLarge && local.editorSizeDanger]}>
                    {editor.kind === "LOADSTRING"
                      ? `${editorChars.toLocaleString("pt-BR")} / ${MAX_LOADSTRING_CHARS.toLocaleString("pt-BR")} caracteres`
                      : `${bytesLabel(editorBytes)} / ${bytesLabel(MAX_CODE_BYTES)}`}
                  </Text>

                  <View style={local.editorActions}>
                    {editor.content ? (
                      <Pressable style={local.secondaryButton} disabled={editorBusy} onPress={() => Clipboard.setStringAsync(editor.content)}>
                        <Text style={local.secondaryButtonText}>COPIAR</Text>
                      </Pressable>
                    ) : null}
                    <Pressable
                      style={[local.saveButton, (editorBusy || editorTooLarge) && local.disabled]}
                      disabled={editorBusy || editorTooLarge}
                      onPress={saveEditor}
                    >
                      <Text style={local.saveButtonText}>{editorBusy ? "SALVANDO..." : "SALVAR NO SERVIDOR"}</Text>
                    </Pressable>
                  </View>
                </>
              ) : null}
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>

      <Modal visible={Boolean(shareTarget)} transparent animationType="fade" onRequestClose={closeShare}>
        <KeyboardAvoidingView style={local.shareKeyboard} behavior={Platform.OS === "ios" ? "padding" : "height"}>
          <ScrollView
            contentContainerStyle={local.shareBackdrop}
            keyboardShouldPersistTaps="handled"
            keyboardDismissMode={Platform.OS === "ios" ? "interactive" : "on-drag"}
          >
            <View style={local.shareModal}>
              <View style={local.editorHeader}>
                <View style={{ flex: 1 }}>
                  <Text style={local.editorEyebrow}>COMPARTILHAR NO FEED</Text>
                  <Text style={local.shareTitle} numberOfLines={2}>{shareTarget?.title || "Arquivo"}</Text>
                </View>
                <Pressable disabled={mutationBusy} onPress={closeShare} accessibilityLabel="Fechar compartilhamento">
                  <Text style={local.close}>✕</Text>
                </Pressable>
              </View>

              <Text style={local.shareHint}>Escreva algo sobre este arquivo, se quiser. O comentário é opcional.</Text>
              <TextInput
                value={shareComment}
                onChangeText={setBoundedShareComment}
                placeholder="Escreva algo sobre esta publicação..."
                placeholderTextColor="#5E5E65"
                style={local.shareInput}
                multiline
                textAlignVertical="top"
                editable={!mutationBusy}
              />
              <Text style={local.shareCounter}>{shareCommentChars}/{MAX_SHARE_COMMENT_CHARS}</Text>

              <Pressable
                style={[local.favoriteChoice, shareFavorite && local.favoriteChoiceActive]}
                disabled={mutationBusy}
                onPress={() => setShareFavorite((value) => !value)}
                accessibilityRole="checkbox"
                accessibilityState={{ checked: shareFavorite }}
              >
                <Text style={[local.favoriteChoiceStar, shareFavorite && local.favoriteChoiceStarActive]}>
                  {shareFavorite ? "★" : "☆"}
                </Text>
                <View style={{ flex: 1 }}>
                  <Text style={local.favoriteChoiceTitle}>Favoritar na biblioteca</Text>
                  <Text style={local.favoriteChoiceHint}>{shareFavorite ? "Será mantido/adicionado aos favoritos ao publicar." : "A publicação não vai favoritar este arquivo."}</Text>
                </View>
              </Pressable>

              <View style={local.editorActions}>
                <Pressable style={local.secondaryButton} disabled={mutationBusy} onPress={closeShare}>
                  <Text style={local.secondaryButtonText}>CANCELAR</Text>
                </Pressable>
                <Pressable style={[local.saveButton, mutationBusy && local.disabled]} disabled={mutationBusy} onPress={submitShare}>
                  <Text style={local.saveButtonText}>{mutationBusy ? "PUBLICANDO..." : "PUBLICAR"}</Text>
                </Pressable>
              </View>
            </View>
          </ScrollView>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const local = StyleSheet.create({
  root: { flex: 1 },
  disabled: { opacity: 0.45 },
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
  favoriteIcon: { color: "#96969D", fontSize: 21 },
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
  itemTitle: { color: "#F3F3F5", fontWeight: "900", fontSize: 14 },
  meta: { color: "#686870", fontSize: 9, marginTop: 4 },
  cardTools: { flexDirection: "row", gap: 6 },
  headerTool: { width: 36, height: 36, borderRadius: 10, borderWidth: 1, borderColor: "#2C2C32", backgroundColor: "#0D0D10", alignItems: "center", justifyContent: "center" },
  headerToolFavorite: { borderColor: "#7A6022", backgroundColor: "#171205" },
  headerStar: { color: "#9A9AA1", fontSize: 20, lineHeight: 22 },
  headerStarActive: { color: "#FFD35A" },
  headerTrash: { borderColor: "#4B2428", backgroundColor: "#13090A" },
  trashIcon: { fontSize: 15 },
  check: { width: 25, height: 25, borderRadius: 99, backgroundColor: "#8653B4", alignItems: "center", justifyContent: "center" },
  checkText: { color: "#FFFFFF", fontSize: 12, fontWeight: "900" },
  preview: { color: "#8D8D94", fontFamily: "monospace", fontSize: 10, lineHeight: 15, marginTop: 12 },
  actions: { flexDirection: "row", gap: 7, marginTop: 12 },
  action: { flex: 1, minHeight: 40, borderRadius: 9, borderWidth: 1, borderColor: "#2A2A30", alignItems: "center", justifyContent: "center", paddingHorizontal: 7 },
  actionText: { color: "#CFCFD3", fontWeight: "900", fontSize: 8 },
  shareAction: { width: 48, minHeight: 40, borderRadius: 9, borderWidth: 1, borderColor: "#4A335D", backgroundColor: "#120C18", alignItems: "center", justifyContent: "center" },
  shareActionIcon: { color: "#D7B5F6", fontSize: 18, fontWeight: "900" },
  loadMoreButton: { minHeight: 48, marginTop: 14, borderRadius: 13, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#0D0D11", alignItems: "center", justifyContent: "center" },
  loadMoreText: { color: "#D7D7DC", fontSize: 10, fontWeight: "900", letterSpacing: 0.5 },
  mediaPlaceholder: { marginTop: 22, minHeight: 260, borderWidth: 1, borderColor: "#25252B", borderRadius: 20, backgroundColor: "#09090C", alignItems: "center", justifyContent: "center", padding: 28 },
  mediaPlus: { width: 96, height: 96, borderRadius: 18, borderWidth: 1, borderStyle: "dashed", borderColor: "#76509A", backgroundColor: "#110B17", alignItems: "center", justifyContent: "center" },
  mediaPlusText: { color: "#C792FF", fontSize: 40 },
  modalKeyboard: { flex: 1 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.92)", justifyContent: "flex-end" },
  editorModal: { height: "92%", backgroundColor: "#070709", borderTopLeftRadius: 22, borderTopRightRadius: 22, borderWidth: 1, borderColor: "#2B2B30", padding: 16 },
  loadstringEditorModal: { height: "64%", minHeight: 380 },
  editorHeader: { flexDirection: "row", alignItems: "flex-start", paddingBottom: 12 },
  editorEyebrow: { color: "#8D5EB5", fontSize: 9, fontWeight: "900", letterSpacing: 1.4 },
  editorTitle: { color: "#FFFFFF", fontSize: 21, fontWeight: "900", marginTop: 4 },
  close: { color: "#A7A7AD", fontSize: 22, padding: 5 },
  nameInput: { minHeight: 50, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#0E0E12", color: "#FFFFFF", paddingHorizontal: 14, fontSize: 15 },
  codeInput: { flex: 1, minHeight: 220, marginTop: 10, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#050507", color: "#DADADF", padding: 14, fontFamily: "monospace", fontSize: 12, lineHeight: 18 },
  loadstringInput: { flex: 0, minHeight: 110, maxHeight: 180 },
  editorSize: { color: "#76767E", fontSize: 10, textAlign: "right", marginTop: 6 },
  editorSizeDanger: { color: "#FF6258", fontWeight: "900" },
  editorActions: { flexDirection: "row", gap: 9, marginTop: 10 },
  secondaryButton: { minHeight: 48, borderRadius: 13, borderWidth: 1, borderColor: "#303036", paddingHorizontal: 18, alignItems: "center", justifyContent: "center" },
  secondaryButtonText: { color: "#E0E0E4", fontSize: 10, fontWeight: "900" },
  saveButton: { flex: 1, minHeight: 48, borderRadius: 13, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 14 },
  saveButtonText: { color: "#050505", fontSize: 10, fontWeight: "900" },
  shareKeyboard: { flex: 1 },
  shareBackdrop: { flexGrow: 1, backgroundColor: "rgba(0,0,0,0.88)", justifyContent: "center", padding: 18 },
  shareModal: { width: "100%", borderRadius: 20, borderWidth: 1, borderColor: "#30263A", backgroundColor: "#09090C", padding: 16 },
  shareTitle: { color: "#FFFFFF", fontSize: 18, fontWeight: "900", marginTop: 4 },
  shareHint: { color: "#85858D", fontSize: 11, lineHeight: 17, marginBottom: 10 },
  shareInput: { minHeight: 105, maxHeight: 180, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#0D0D11", color: "#FFFFFF", padding: 12, fontSize: 13 },
  shareCounter: { color: "#6C6C74", fontSize: 9, textAlign: "right", marginTop: 5 },
  favoriteChoice: { flexDirection: "row", alignItems: "center", gap: 11, marginTop: 10, borderRadius: 13, borderWidth: 1, borderColor: "#2C2C32", backgroundColor: "#0D0D10", padding: 12 },
  favoriteChoiceActive: { borderColor: "#7A6022", backgroundColor: "#171205" },
  favoriteChoiceStar: { color: "#9999A0", fontSize: 24 },
  favoriteChoiceStarActive: { color: "#FFD35A" },
  favoriteChoiceTitle: { color: "#E9E9EC", fontSize: 12, fontWeight: "900" },
  favoriteChoiceHint: { color: "#777780", fontSize: 9, lineHeight: 14, marginTop: 3 }
});
