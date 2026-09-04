import { useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Crypto from "expo-crypto";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";

type MediaKind = "PHOTO" | "VIDEO";

type StoredMedia = {
  id: string;
  kind: MediaKind;
  name: string;
  fileName: string;
  mimeType: string | null;
  size: number;
  importedAt: string;
};

type VaultState = {
  version: 1;
  items: StoredMedia[];
};

const PHOTO_LIMIT_BYTES = 30 * 1024 * 1024;
const VIDEO_LIMIT_BYTES = 300 * 1024 * 1024;
const MAX_MEDIA_ITEMS = 500;
const METADATA_FILE = "vault.json";

function bytesLabel(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "tamanho desconhecido";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(bytes >= 10 * 1024 * 1024 ? 0 : 1)} MB`;
}

function dateText(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function safeExtension(name: string) {
  const match = String(name || "").match(/(\.[a-zA-Z0-9]{1,8})$/);
  return match ? match[1].toLowerCase() : "";
}

function safeDisplayName(name: string, fallback: string) {
  const normalized = String(name || "")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .slice(0, 120);
  return normalized || fallback;
}

function mediaLimit(kind: MediaKind) {
  return kind === "PHOTO" ? PHOTO_LIMIT_BYTES : VIDEO_LIMIT_BYTES;
}

function mediaType(kind: MediaKind) {
  return kind === "PHOTO" ? "image/*" : "video/*";
}

function normalizeVault(value: unknown): VaultState {
  if (!value || typeof value !== "object") return { version: 1, items: [] };
  const raw = value as { items?: unknown };
  if (!Array.isArray(raw.items)) return { version: 1, items: [] };

  const items: StoredMedia[] = [];
  for (const candidate of raw.items) {
    if (!candidate || typeof candidate !== "object") continue;
    const item = candidate as Partial<StoredMedia>;
    if (
      typeof item.id !== "string" ||
      (item.kind !== "PHOTO" && item.kind !== "VIDEO") ||
      typeof item.name !== "string" ||
      typeof item.fileName !== "string" ||
      typeof item.importedAt !== "string"
    ) continue;
    items.push({
      id: item.id,
      kind: item.kind,
      name: item.name,
      fileName: item.fileName,
      mimeType: typeof item.mimeType === "string" ? item.mimeType : null,
      size: typeof item.size === "number" && Number.isFinite(item.size) ? Math.max(0, item.size) : 0,
      importedAt: item.importedAt
    });
  }
  return { version: 1, items: items.slice(0, MAX_MEDIA_ITEMS) };
}

async function namespaceForDevice(deviceToken: string) {
  const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, `grupo-lua-media:${deviceToken}`);
  return hash.slice(0, 24);
}

async function ensureVaultDirectory(deviceToken: string) {
  const root = FileSystem.documentDirectory;
  if (!root) throw new Error("O armazenamento interno do aplicativo não está disponível neste aparelho.");
  const namespace = await namespaceForDevice(deviceToken);
  const base = `${root}grupo-lua-media/${namespace}/`;
  await FileSystem.makeDirectoryAsync(base, { intermediates: true });
  return base;
}

async function persistVault(base: string, items: StoredMedia[]) {
  const payload: VaultState = { version: 1, items };
  await FileSystem.writeAsStringAsync(`${base}${METADATA_FILE}`, JSON.stringify(payload), {
    encoding: FileSystem.EncodingType.UTF8
  });
}

export function LocalMediaVault({ deviceToken }: { deviceToken: string }) {
  const [kind, setKind] = useState<MediaKind>("PHOTO");
  const [items, setItems] = useState<StoredMedia[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [base, setBase] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const mounted = useRef(true);
  const mutationLock = useRef(false);

  async function loadVault() {
    setLoading(true);
    setMessage(null);
    try {
      const directory = await ensureVaultDirectory(deviceToken);
      const metadataUri = `${directory}${METADATA_FILE}`;
      const metadataInfo = await FileSystem.getInfoAsync(metadataUri);
      let next: StoredMedia[] = [];

      if (metadataInfo.exists) {
        try {
          const raw = await FileSystem.readAsStringAsync(metadataUri, { encoding: FileSystem.EncodingType.UTF8 });
          next = normalizeVault(JSON.parse(raw)).items;
        } catch {
          next = [];
        }
      }

      const verified: StoredMedia[] = [];
      let pruned = false;
      for (const item of next) {
        const info = await FileSystem.getInfoAsync(`${directory}${item.fileName}`, { size: true });
        if (!info.exists) {
          pruned = true;
          continue;
        }
        verified.push({
          ...item,
          size: typeof info.size === "number" && info.size > 0 ? info.size : item.size
        });
      }
      if (pruned) await persistVault(directory, verified);

      if (!mounted.current) return;
      setBase(directory);
      setItems(verified);
    } catch (error) {
      if (mounted.current) {
        setBase(null);
        setItems([]);
        setMessage(error instanceof Error ? error.message : "Não foi possível abrir a mídia local.");
      }
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

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

  async function importMedia() {
    if (!base || !beginMutation()) return;
    try {
      if (items.length >= MAX_MEDIA_ITEMS) {
        Alert.alert("Limite local", `O cofre aceita até ${MAX_MEDIA_ITEMS} itens neste aparelho.`);
        return;
      }

      const result = await DocumentPicker.getDocumentAsync({
        type: mediaType(kind),
        copyToCacheDirectory: true,
        multiple: false
      });
      if (result.canceled || !result.assets?.[0]) return;

      const asset = result.assets[0];
      const info = await FileSystem.getInfoAsync(asset.uri, { size: true });
      const size = typeof info.size === "number" ? info.size : typeof asset.size === "number" ? asset.size : 0;
      const limit = mediaLimit(kind);
      if (size > limit) {
        Alert.alert(
          "Arquivo muito grande",
          `${kind === "PHOTO" ? "Fotos" : "Vídeos"} podem ter no máximo ${bytesLabel(limit)} nesta versão.`
        );
        return;
      }

      const id = Crypto.randomUUID();
      const extension = safeExtension(asset.name || "") || (kind === "PHOTO" ? ".img" : ".video");
      const fileName = `${id}${extension}`;
      const destination = `${base}${fileName}`;
      await FileSystem.copyAsync({ from: asset.uri, to: destination });

      const copied = await FileSystem.getInfoAsync(destination, { size: true });
      if (!copied.exists) throw new Error("A cópia local da mídia não pôde ser confirmada.");

      const item: StoredMedia = {
        id,
        kind,
        name: safeDisplayName(asset.name || "", kind === "PHOTO" ? "Foto" : "Vídeo"),
        fileName,
        mimeType: asset.mimeType || null,
        size: typeof copied.size === "number" ? copied.size : size,
        importedAt: new Date().toISOString()
      };
      const next = [item, ...items].slice(0, MAX_MEDIA_ITEMS);
      try {
        await persistVault(base, next);
      } catch (error) {
        await FileSystem.deleteAsync(destination, { idempotent: true }).catch(() => {});
        throw error;
      }

      if (mounted.current) {
        setItems(next);
        setMessage(`${item.name} foi copiado para o armazenamento privado do App 1.`);
      }
    } catch (error) {
      if (mounted.current) Alert.alert("Não foi possível importar", error instanceof Error ? error.message : "Falha ao guardar a mídia.");
    } finally {
      endMutation();
    }
  }

  function confirmDelete(item: StoredMedia) {
    if (!base || mutationLock.current) return;
    Alert.alert(
      `Apagar ${item.kind === "PHOTO" ? "foto" : "vídeo"}?`,
      "A cópia guardada dentro do App 1 será removida do aparelho. O arquivo original de onde ela foi importada não é apagado.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Apagar",
          style: "destructive",
          onPress: () => {
            if (!beginMutation()) return;
            (async () => {
              try {
                const next = items.filter((value) => value.id !== item.id);
                await FileSystem.deleteAsync(`${base}${item.fileName}`, { idempotent: true });
                await persistVault(base, next);
                if (mounted.current) {
                  setItems(next);
                  setMessage(`${item.name} foi removido do cofre local.`);
                }
              } catch (error) {
                if (mounted.current) Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível remover a mídia.");
              } finally {
                endMutation();
              }
            })().catch(() => {});
          }
        }
      ]
    );
  }

  useEffect(() => {
    mounted.current = true;
    loadVault().catch(() => {});
    return () => { mounted.current = false; };
  }, [deviceToken]);

  const visible = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("pt-BR");
    return items.filter((item) => {
      if (item.kind !== kind) return false;
      if (!normalized) return true;
      return item.name.toLocaleLowerCase("pt-BR").includes(normalized);
    });
  }, [items, kind, query]);

  const counts = useMemo(() => ({
    photo: items.filter((item) => item.kind === "PHOTO").length,
    video: items.filter((item) => item.kind === "VIDEO").length,
    bytes: items.reduce((total, item) => total + Math.max(0, item.size), 0)
  }), [items]);

  return (
    <View style={s.root}>
      <View style={s.hero}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>Mídia local</Text>
          <Text style={s.subtitle}>Fotos e vídeos ficam somente no armazenamento privado deste App 1 neste aparelho.</Text>
        </View>
        <Pressable style={[s.refresh, busy && s.disabled]} disabled={busy} onPress={() => { loadVault().catch(() => {}); }}>
          <Text style={s.refreshText}>↻</Text>
        </Pressable>
      </View>

      <View style={s.privacyCard}>
        <Text style={s.privacyTitle}>LOCAL • NÃO ENVIADO AO SERVIDOR</Text>
        <Text style={s.privacyText}>Importar cria uma cópia dentro do armazenamento privado do aplicativo. Esta área não publica fotos ou vídeos no Social e não sincroniza a mídia entre celulares.</Text>
      </View>

      <View style={s.tabs}>
        <Pressable style={[s.tab, kind === "PHOTO" && s.tabActive]} disabled={busy} onPress={() => setKind("PHOTO")}>
          <Text style={[s.tabText, kind === "PHOTO" && s.tabTextActive]}>FOTOS • {counts.photo}</Text>
        </Pressable>
        <Pressable style={[s.tab, kind === "VIDEO" && s.tabActive]} disabled={busy} onPress={() => setKind("VIDEO")}>
          <Text style={[s.tabText, kind === "VIDEO" && s.tabTextActive]}>VÍDEOS • {counts.video}</Text>
        </Pressable>
      </View>

      <View style={s.summary}>
        <Text style={s.summaryText}>{items.length} item(ns) • {bytesLabel(counts.bytes)} usados pelo cofre</Text>
        <Text style={s.summaryLimit}>{kind === "PHOTO" ? `até ${bytesLabel(PHOTO_LIMIT_BYTES)} por foto` : `até ${bytesLabel(VIDEO_LIMIT_BYTES)} por vídeo`}</Text>
      </View>

      <View style={s.searchRow}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          editable={!busy}
          style={s.search}
          placeholder={`Buscar ${kind === "PHOTO" ? "fotos" : "vídeos"}...`}
          placeholderTextColor="#66666E"
        />
        <Pressable style={[s.importButton, (!base || busy) && s.disabled]} disabled={!base || busy} onPress={() => { importMedia().catch(() => {}); }}>
          <Text style={s.importText}>{busy ? "..." : "＋ IMPORTAR"}</Text>
        </Pressable>
      </View>

      {message ? <Text style={s.message}>{message}</Text> : null}
      {loading ? <ActivityIndicator style={{ marginVertical: 28 }} /> : null}

      {!loading && visible.length === 0 ? (
        <View style={s.empty}>
          <Text style={s.emptyIcon}>{kind === "PHOTO" ? "▧" : "▷"}</Text>
          <Text style={s.emptyTitle}>Nenhum {kind === "PHOTO" ? "foto" : "vídeo"} guardado</Text>
          <Text style={s.emptyText}>Use IMPORTAR para selecionar um arquivo do celular e criar uma cópia privada dentro do App 1.</Text>
        </View>
      ) : null}

      {!loading ? visible.map((item) => {
        const uri = base ? `${base}${item.fileName}` : "";
        return (
          <View key={item.id} style={s.card}>
            {item.kind === "PHOTO" && uri ? (
              <Image source={{ uri }} style={s.photo} resizeMode="cover" />
            ) : (
              <View style={s.videoThumb}><Text style={s.videoGlyph}>▷</Text><Text style={s.videoLabel}>VÍDEO LOCAL</Text></View>
            )}
            <View style={s.cardBody}>
              <Text numberOfLines={2} style={s.name}>{item.name}</Text>
              <Text style={s.meta}>{bytesLabel(item.size)} • {dateText(item.importedAt)}</Text>
              {item.mimeType ? <Text style={s.mime}>{item.mimeType}</Text> : null}
              <View style={s.actions}>
                <Pressable style={[s.delete, busy && s.disabled]} disabled={busy} onPress={() => confirmDelete(item)}>
                  <Text style={s.deleteText}>APAGAR CÓPIA LOCAL</Text>
                </Pressable>
              </View>
            </View>
          </View>
        );
      }) : null}

      <View style={s.note}>
        <Text style={s.noteTitle}>Sobre vídeos</Text>
        <Text style={s.noteText}>Esta primeira versão do cofre já importa, preserva, lista e apaga vídeos localmente. A reprodução dentro do próprio App 1 será adicionada separadamente para não arriscar a estabilidade da build Android.</Text>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  hero: { flexDirection: "row", alignItems: "center", gap: 9 },
  title: { color: "#FFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "#77777F", fontSize: 10, lineHeight: 15, marginTop: 4 },
  refresh: { width: 42, height: 42, borderRadius: 12, borderWidth: 1, borderColor: "#303036", alignItems: "center", justifyContent: "center" },
  refreshText: { color: "#CCAFDF", fontSize: 18 },
  privacyCard: { borderRadius: 14, borderWidth: 1, borderColor: "#2B2430", backgroundColor: "#0D0910", padding: 12, marginTop: 12 },
  privacyTitle: { color: "#D3B6E7", fontSize: 8, fontWeight: "900", letterSpacing: 0.7 },
  privacyText: { color: "#7D7285", fontSize: 9, lineHeight: 15, marginTop: 5 },
  tabs: { flexDirection: "row", gap: 8, marginTop: 13 },
  tab: { flex: 1, minHeight: 42, borderRadius: 11, borderWidth: 1, borderColor: "#303036", alignItems: "center", justifyContent: "center" },
  tabActive: { backgroundColor: "#FFF", borderColor: "#FFF" },
  tabText: { color: "#8A8A92", fontSize: 8, fontWeight: "900" },
  tabTextActive: { color: "#050505" },
  summary: { flexDirection: "row", justifyContent: "space-between", flexWrap: "wrap", gap: 6, marginTop: 10 },
  summaryText: { color: "#73737B", fontSize: 8 },
  summaryLimit: { color: "#5F5F67", fontSize: 8 },
  searchRow: { flexDirection: "row", gap: 8, marginTop: 10 },
  search: { flex: 1, minHeight: 47, borderRadius: 12, borderWidth: 1, borderColor: "#2B2B31", backgroundColor: "#0D0D10", color: "#FFF", paddingHorizontal: 12 },
  importButton: { minWidth: 104, minHeight: 47, borderRadius: 12, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  importText: { color: "#050505", fontSize: 8, fontWeight: "900" },
  message: { color: "#BBA3CE", fontSize: 9, lineHeight: 14, marginTop: 8 },
  empty: { borderRadius: 18, borderWidth: 1, borderColor: "#25252B", backgroundColor: "#09090C", padding: 25, alignItems: "center", marginTop: 14 },
  emptyIcon: { color: "#B591CE", fontSize: 30 },
  emptyTitle: { color: "#FFF", fontSize: 14, fontWeight: "900", marginTop: 8 },
  emptyText: { color: "#77777F", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 6 },
  card: { flexDirection: "row", borderRadius: 16, borderWidth: 1, borderColor: "#27272D", backgroundColor: "#09090C", overflow: "hidden", marginTop: 10, minHeight: 118 },
  photo: { width: 118, minHeight: 118, backgroundColor: "#111114" },
  videoThumb: { width: 118, minHeight: 118, backgroundColor: "#100B13", alignItems: "center", justifyContent: "center" },
  videoGlyph: { color: "#C49BDD", fontSize: 26 },
  videoLabel: { color: "#745D82", fontSize: 7, fontWeight: "900", marginTop: 5 },
  cardBody: { flex: 1, padding: 12 },
  name: { color: "#FFF", fontSize: 12, fontWeight: "900", lineHeight: 17 },
  meta: { color: "#74747C", fontSize: 8, marginTop: 5 },
  mime: { color: "#5C5C64", fontSize: 7, marginTop: 3 },
  actions: { flexDirection: "row", marginTop: "auto", paddingTop: 10 },
  delete: { borderRadius: 8, borderWidth: 1, borderColor: "#4A2429", backgroundColor: "#120708", paddingHorizontal: 9, paddingVertical: 7 },
  deleteText: { color: "#E56D74", fontSize: 7, fontWeight: "900" },
  note: { borderRadius: 14, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#08080A", padding: 12, marginTop: 14 },
  noteTitle: { color: "#FFF", fontSize: 10, fontWeight: "900" },
  noteText: { color: "#707078", fontSize: 9, lineHeight: 15, marginTop: 5 },
  disabled: { opacity: 0.42 }
});
