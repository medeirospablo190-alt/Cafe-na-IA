import { useEffect, useMemo, useRef, useState } from "react";
import { useEvent } from "expo";
import {
  ActivityIndicator,
  Alert,
  Image,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Crypto from "expo-crypto";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";
import { useVideoPlayer, VideoView } from "expo-video";
import { getApp1InstallationId } from "./device";

export type MediaKind = "PHOTO" | "VIDEO";

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

type PreviewState = {
  item: StoredMedia;
  uri: string;
};

const PHOTO_LIMIT_BYTES = 30 * 1024 * 1024;
const VIDEO_LIMIT_BYTES = 300 * 1024 * 1024;
const VAULT_LIMIT_BYTES = 1024 * 1024 * 1024;
const FREE_SPACE_RESERVE_BYTES = 64 * 1024 * 1024;
const MAX_MEDIA_ITEMS = 500;
const INITIAL_VISIBLE_ITEMS = 40;
const METADATA_FILE = "vault.json";
const METADATA_TEMP_FILE = "vault.json.tmp";
const METADATA_BACKUP_FILE = "vault.json.bak";

const PHOTO_EXTENSIONS = new Set([
  ".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif", ".bmp", ".avif", ".img"
]);
const VIDEO_EXTENSIONS = new Set([
  ".mp4", ".m4v", ".mov", ".webm", ".3gp", ".mkv", ".avi", ".video"
]);

const MIME_EXTENSION: Record<string, string> = {
  "image/jpeg": ".jpg",
  "image/png": ".png",
  "image/webp": ".webp",
  "image/gif": ".gif",
  "image/heic": ".heic",
  "image/heif": ".heif",
  "image/bmp": ".bmp",
  "image/avif": ".avif",
  "video/mp4": ".mp4",
  "video/quicktime": ".mov",
  "video/webm": ".webm",
  "video/3gpp": ".3gp",
  "video/x-matroska": ".mkv",
  "video/x-msvideo": ".avi"
};

function bytesLabel(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(bytes >= 10 * 1024 * 1024 ? 0 : 1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function dateText(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "—"
    : date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
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

function kindFromExtension(extension: string): MediaKind | null {
  if (PHOTO_EXTENSIONS.has(extension)) return "PHOTO";
  if (VIDEO_EXTENSIONS.has(extension)) return "VIDEO";
  return null;
}

function kindFromAsset(name: string, mimeType: string | null | undefined): MediaKind | null {
  const mime = String(mimeType || "").toLowerCase();
  if (mime.startsWith("image/")) return "PHOTO";
  if (mime.startsWith("video/")) return "VIDEO";
  return kindFromExtension(safeExtension(name));
}

function extensionForAsset(kind: MediaKind, name: string, mimeType: string | null | undefined) {
  const extension = safeExtension(name);
  if (kindFromExtension(extension) === kind) return extension;
  const mapped = MIME_EXTENSION[String(mimeType || "").toLowerCase()];
  if (mapped && kindFromExtension(mapped) === kind) return mapped;
  return kind === "PHOTO" ? ".img" : ".video";
}

function mimeForExtension(extension: string) {
  const entry = Object.entries(MIME_EXTENSION).find(([, candidate]) => candidate === extension);
  return entry?.[0] || null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object";
}

function infoExists(value: unknown): value is Record<string, unknown> {
  return isRecord(value) && value.exists === true;
}

function infoSize(value: unknown) {
  if (!infoExists(value)) return 0;
  const size = value.size;
  return typeof size === "number" && Number.isFinite(size) && size > 0 ? size : 0;
}

function infoDate(value: unknown) {
  if (!infoExists(value)) return new Date().toISOString();
  const raw = value.modificationTime;
  if (typeof raw !== "number" || !Number.isFinite(raw) || raw <= 0) return new Date().toISOString();
  const milliseconds = raw < 1_000_000_000_000 ? raw * 1000 : raw;
  const date = new Date(milliseconds);
  return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
}

function validStoredFileName(id: string, fileName: string) {
  const escapedId = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${escapedId}\\.[a-zA-Z0-9]{1,8}$`).test(fileName);
}

function normalizeVault(value: unknown): VaultState {
  if (!isRecord(value) || !Array.isArray(value.items)) {
    throw new Error("Índice de mídia inválido.");
  }

  const items: StoredMedia[] = [];
  const seen = new Set<string>();
  for (const candidate of value.items) {
    if (!isRecord(candidate)) continue;
    const id = typeof candidate.id === "string" ? candidate.id.trim() : "";
    const kind = candidate.kind;
    const fileName = typeof candidate.fileName === "string" ? candidate.fileName.trim() : "";
    const importedAt = typeof candidate.importedAt === "string" ? candidate.importedAt : "";
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id) ||
      (kind !== "PHOTO" && kind !== "VIDEO") ||
      !validStoredFileName(id, fileName) ||
      Number.isNaN(new Date(importedAt).getTime()) ||
      seen.has(id)
    ) continue;

    seen.add(id);
    items.push({
      id,
      kind,
      name: safeDisplayName(
        typeof candidate.name === "string" ? candidate.name : "",
        kind === "PHOTO" ? "Foto" : "Vídeo"
      ),
      fileName,
      mimeType: typeof candidate.mimeType === "string" ? candidate.mimeType.slice(0, 128) : null,
      size: typeof candidate.size === "number" && Number.isFinite(candidate.size)
        ? Math.max(0, candidate.size)
        : 0,
      importedAt
    });
  }

  return {
    version: 1,
    items: items
      .sort((a, b) => b.importedAt.localeCompare(a.importedAt))
      .slice(0, MAX_MEDIA_ITEMS)
  };
}

async function namespaceForOwner(ownerId: string) {
  const installationId = await getApp1InstallationId();
  const hash = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    `grupo-lua-media:v2:${installationId}:${ownerId}`
  );
  return hash.slice(0, 32);
}

async function ensureVaultDirectory(ownerId: string) {
  const root = FileSystem.documentDirectory;
  if (!root) throw new Error("O armazenamento interno do aplicativo não está disponível neste aparelho.");
  const namespace = await namespaceForOwner(ownerId);
  const base = `${root}grupo-lua-media/${namespace}/`;
  await FileSystem.makeDirectoryAsync(base, { intermediates: true });
  return base;
}

async function readMetadataCandidate(uri: string) {
  const info = await FileSystem.getInfoAsync(uri);
  if (!infoExists(info)) return { exists: false, items: null as StoredMedia[] | null };
  const raw = await FileSystem.readAsStringAsync(uri, { encoding: FileSystem.EncodingType.UTF8 });
  return { exists: true, items: normalizeVault(JSON.parse(raw)).items };
}

async function readVaultIndex(base: string) {
  const candidates = [
    { source: "primary" as const, uri: `${base}${METADATA_FILE}` },
    { source: "temporary" as const, uri: `${base}${METADATA_TEMP_FILE}` },
    { source: "backup" as const, uri: `${base}${METADATA_BACKUP_FILE}` }
  ];
  let corrupt = false;

  for (const candidate of candidates) {
    try {
      const result = await readMetadataCandidate(candidate.uri);
      if (!result.exists) continue;
      if (result.items) return { items: result.items, source: candidate.source, corrupt };
    } catch {
      corrupt = true;
    }
  }

  return { items: [] as StoredMedia[], source: "empty" as const, corrupt };
}

async function persistVault(base: string, items: StoredMedia[], backupCurrent = true) {
  const primary = `${base}${METADATA_FILE}`;
  const temporary = `${base}${METADATA_TEMP_FILE}`;
  const backup = `${base}${METADATA_BACKUP_FILE}`;
  const payload: VaultState = { version: 1, items };

  await FileSystem.writeAsStringAsync(temporary, JSON.stringify(payload), {
    encoding: FileSystem.EncodingType.UTF8
  });

  const primaryInfo = await FileSystem.getInfoAsync(primary);
  if (backupCurrent && infoExists(primaryInfo)) {
    await FileSystem.deleteAsync(backup, { idempotent: true });
    await FileSystem.copyAsync({ from: primary, to: backup });
  }

  await FileSystem.deleteAsync(primary, { idempotent: true });
  try {
    await FileSystem.moveAsync({ from: temporary, to: primary });
  } catch (error) {
    const backupInfo = await FileSystem.getInfoAsync(backup).catch(() => null);
    const restoredInfo = await FileSystem.getInfoAsync(primary).catch(() => null);
    if (!infoExists(restoredInfo) && infoExists(backupInfo)) {
      await FileSystem.copyAsync({ from: backup, to: primary }).catch(() => {});
    }
    throw error;
  }
}

async function verifyStoredItems(base: string, items: StoredMedia[]) {
  const verified: StoredMedia[] = [];
  let missing = 0;
  let changed = false;

  for (let offset = 0; offset < items.length; offset += 24) {
    const batch = items.slice(offset, offset + 24);
    const results = await Promise.all(batch.map(async (item) => {
      const info = await FileSystem.getInfoAsync(`${base}${item.fileName}`).catch(() => null);
      if (!infoExists(info)) return null;
      const size = infoSize(info);
      return size > 0 && size !== item.size ? { ...item, size } : item;
    }));

    results.forEach((item, index) => {
      if (!item) {
        missing += 1;
        return;
      }
      if (item.size !== batch[index].size) changed = true;
      verified.push(item);
    });
  }

  return { items: verified, missing, changed };
}

async function recoverStoredFiles(base: string, knownItems: StoredMedia[]) {
  const knownFiles = new Set(knownItems.map((item) => item.fileName));
  const entries = await FileSystem.readDirectoryAsync(base).catch(() => [] as string[]);
  const recovered: StoredMedia[] = [];
  const availableSlots = Math.max(0, MAX_MEDIA_ITEMS - knownItems.length);

  for (const fileName of entries) {
    if (recovered.length >= availableSlots || knownFiles.has(fileName)) continue;
    const match = /^([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})(\.[a-z0-9]{1,8})$/i.exec(fileName);
    if (!match) continue;
    const kind = kindFromExtension(match[2].toLowerCase());
    if (!kind) continue;
    const info = await FileSystem.getInfoAsync(`${base}${fileName}`).catch(() => null);
    if (!infoExists(info)) continue;
    recovered.push({
      id: match[1],
      kind,
      name: `${kind === "PHOTO" ? "Foto" : "Vídeo"} recuperado ${match[1].slice(0, 8)}`,
      fileName,
      mimeType: mimeForExtension(match[2].toLowerCase()),
      size: infoSize(info),
      importedAt: infoDate(info)
    });
  }

  return recovered;
}

async function removePickedCacheCopy(uri: string | null) {
  const cacheRoot = FileSystem.cacheDirectory;
  if (!uri || !cacheRoot || !uri.startsWith(cacheRoot)) return;
  await FileSystem.deleteAsync(uri, { idempotent: true }).catch(() => {});
}

function LocalVideoPreview({ uri }: { uri: string }) {
  const player = useVideoPlayer(uri);
  const { status } = useEvent(player, "statusChange", {
    status: player.status
  });

  return (
    <View style={s.videoPreviewRoot}>
      <VideoView
        player={player}
        style={s.videoPlayer}
        contentFit="contain"
        nativeControls
        fullscreenOptions={{ enable: true }}
      />
      {status === "loading" ? (
        <View style={s.playerOverlay} pointerEvents="none">
          <ActivityIndicator />
          <Text style={s.playerOverlayText}>Carregando vídeo local...</Text>
        </View>
      ) : null}
      {status === "error" ? (
        <View style={s.playerError}>
          <Text style={s.playerErrorTitle}>Não foi possível reproduzir este vídeo.</Text>
          <Text style={s.playerErrorText}>O arquivo pode estar corrompido ou usar um formato que este aparelho não reconhece.</Text>
        </View>
      ) : null}
    </View>
  );
}

export function LocalMediaVault({ kind, ownerId }: {
  kind: MediaKind;
  ownerId: string;
}) {
  const [items, setItems] = useState<StoredMedia[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [base, setBase] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [preview, setPreview] = useState<PreviewState | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);
  const [brokenIds, setBrokenIds] = useState<string[]>([]);
  const [visibleCount, setVisibleCount] = useState(INITIAL_VISIBLE_ITEMS);
  const mounted = useRef(true);
  const mutationLock = useRef(false);
  const loadVersion = useRef(0);

  async function loadVault() {
    const version = ++loadVersion.current;
    setLoading(true);
    setMessage(null);
    try {
      const directory = await ensureVaultDirectory(ownerId);
      const index = await readVaultIndex(directory);
      const verified = await verifyStoredItems(directory, index.items);
      const recovered = await recoverStoredFiles(directory, verified.items);
      const next = [...verified.items, ...recovered]
        .sort((a, b) => b.importedAt.localeCompare(a.importedAt))
        .slice(0, MAX_MEDIA_ITEMS);
      const shouldRepair = index.source !== "primary" || verified.missing > 0 || verified.changed || recovered.length > 0;
      const notices: string[] = [];

      if (shouldRepair) {
        try {
          await persistVault(directory, next, index.source === "primary");
        } catch {
          notices.push("A mídia foi carregada, mas o índice local não pôde ser reparado agora.");
        }
      }
      if (index.corrupt || index.source === "backup" || index.source === "temporary") {
        notices.push("O índice local foi recuperado com segurança.");
      }
      if (verified.missing > 0) {
        notices.push(`${verified.missing} arquivo(s) removido(s) do celular foram retirados da lista.`);
      }
      if (recovered.length > 0) {
        notices.push(`${recovered.length} arquivo(s) local(is) foram recuperados.`);
      }

      if (!mounted.current || version !== loadVersion.current) return;
      setBase(directory);
      setItems(next);
      setBrokenIds([]);
      setMessage(notices.length ? notices.join(" ") : null);
    } catch (error) {
      if (mounted.current && version === loadVersion.current) {
        setBase(null);
        setItems([]);
        setMessage(error instanceof Error ? error.message : "Não foi possível abrir a mídia local.");
      }
    } finally {
      if (mounted.current && version === loadVersion.current) setLoading(false);
    }
  }

  function beginMutation() {
    if (mutationLock.current || loading) return false;
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
    let pickedUri: string | null = null;
    let destinationUri: string | null = null;
    let importCommitted = false;
    try {
      if (items.length >= MAX_MEDIA_ITEMS) {
        Alert.alert("Limite local", `O cofre aceita até ${MAX_MEDIA_ITEMS} itens nesta instalação.`);
        return;
      }

      setMessage(`Selecione ${kind === "PHOTO" ? "uma foto" : "um vídeo"} no aparelho.`);
      const result = await DocumentPicker.getDocumentAsync({
        type: mediaType(kind),
        copyToCacheDirectory: true,
        multiple: false
      });
      if (result.canceled || !result.assets?.[0]) {
        setMessage(null);
        return;
      }

      const asset = result.assets[0];
      pickedUri = asset.uri;
      if (kindFromAsset(asset.name || "", asset.mimeType) !== kind) {
        throw new Error(`O arquivo selecionado não foi reconhecido como ${kind === "PHOTO" ? "foto" : "vídeo"}.`);
      }

      const sourceInfo = await FileSystem.getInfoAsync(asset.uri).catch(() => null);
      const size = infoSize(sourceInfo) || (typeof asset.size === "number" ? Math.max(0, asset.size) : 0);
      if (size <= 0) throw new Error("Não foi possível confirmar o tamanho do arquivo selecionado.");

      const itemLimit = mediaLimit(kind);
      if (size > itemLimit) {
        throw new Error(`${kind === "PHOTO" ? "Fotos" : "Vídeos"} podem ter no máximo ${bytesLabel(itemLimit)}.`);
      }

      const usedBytes = items.reduce((total, item) => total + Math.max(0, item.size), 0);
      if (usedBytes + size > VAULT_LIMIT_BYTES) {
        throw new Error(`O cofre local aceita até ${bytesLabel(VAULT_LIMIT_BYTES)}. Apague algum item antes de importar.`);
      }

      const freeBytes = await FileSystem.getFreeDiskStorageAsync().catch(() => null);
      if (typeof freeBytes === "number" && freeBytes < size + FREE_SPACE_RESERVE_BYTES) {
        throw new Error(`Não há espaço livre suficiente. O App 1 preserva pelo menos ${bytesLabel(FREE_SPACE_RESERVE_BYTES)} livres no aparelho.`);
      }

      const id = Crypto.randomUUID();
      const extension = extensionForAsset(kind, asset.name || "", asset.mimeType);
      const fileName = `${id}${extension}`;
      const destination = `${base}${fileName}`;
      destinationUri = destination;
      setMessage(`Copiando ${kind === "PHOTO" ? "foto" : "vídeo"} para o cofre privado...`);
      await FileSystem.copyAsync({ from: asset.uri, to: destination });

      const copiedInfo = await FileSystem.getInfoAsync(destination).catch(() => null);
      if (!infoExists(copiedInfo)) throw new Error("A cópia local da mídia não pôde ser confirmada.");
      const copiedSize = infoSize(copiedInfo) || size;
      if (copiedSize > itemLimit || usedBytes + copiedSize > VAULT_LIMIT_BYTES) {
        await FileSystem.deleteAsync(destination, { idempotent: true }).catch(() => {});
        throw new Error("A cópia excedeu o limite permitido e foi cancelada.");
      }

      const item: StoredMedia = {
        id,
        kind,
        name: safeDisplayName(asset.name || "", kind === "PHOTO" ? "Foto" : "Vídeo"),
        fileName,
        mimeType: asset.mimeType || mimeForExtension(extension),
        size: copiedSize,
        importedAt: new Date().toISOString()
      };
      const next = [item, ...items].slice(0, MAX_MEDIA_ITEMS);
      await persistVault(base, next);
      importCommitted = true;

      if (mounted.current) {
        setItems(next);
        setVisibleCount((current) => Math.max(current, 1));
        setMessage(`${item.name} foi copiado para o armazenamento privado do App 1.`);
      }
    } catch (error) {
      if (destinationUri && !importCommitted) {
        await FileSystem.deleteAsync(destinationUri, { idempotent: true }).catch(() => {});
      }
      if (mounted.current) {
        setMessage(null);
        Alert.alert("Não foi possível importar", error instanceof Error ? error.message : "Falha ao guardar a mídia.");
      }
    } finally {
      await removePickedCacheCopy(pickedUri);
      endMutation();
    }
  }

  async function deleteItem(item: StoredMedia) {
    if (!base || !beginMutation()) return;
    if (preview?.item.id === item.id) {
      setPreview(null);
      await new Promise<void>((resolve) => setTimeout(resolve, 0));
    }
    const source = `${base}${item.fileName}`;
    const trash = `${base}.trash-${item.id}-${Date.now()}`;
    let staged = false;
    try {
      const sourceInfo = await FileSystem.getInfoAsync(source).catch(() => null);
      if (infoExists(sourceInfo)) {
        await FileSystem.moveAsync({ from: source, to: trash });
        staged = true;
      }

      const next = items.filter((value) => value.id !== item.id);
      try {
        await persistVault(base, next);
      } catch (error) {
        if (staged) await FileSystem.moveAsync({ from: trash, to: source }).catch(() => {});
        throw error;
      }

      if (staged) await FileSystem.deleteAsync(trash, { idempotent: true }).catch(() => {});
      if (mounted.current) {
        setItems(next);
        setPreview((current) => current?.item.id === item.id ? null : current);
        setBrokenIds((current) => current.filter((id) => id !== item.id));
        setMessage(`${item.name} foi removido do cofre local.`);
      }
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível remover a mídia.");
      }
    } finally {
      endMutation();
    }
  }

  function confirmDelete(item: StoredMedia) {
    if (!base || mutationLock.current) return;
    Alert.alert(
      `Apagar ${item.kind === "PHOTO" ? "foto" : "vídeo"}?`,
      "A cópia guardada dentro do App 1 será removida. O arquivo original de onde ela foi importada não é apagado.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Apagar",
          style: "destructive",
          onPress: () => { deleteItem(item).catch(() => {}); }
        }
      ]
    );
  }

  async function openPreview(item: StoredMedia) {
    if (!base || busy) return;
    const uri = `${base}${item.fileName}`;
    const info = await FileSystem.getInfoAsync(uri).catch(() => null);
    if (!infoExists(info)) {
      Alert.alert("Arquivo removido", "Esta mídia não existe mais no armazenamento do aparelho. A lista será atualizada.");
      await loadVault();
      return;
    }
    setPreviewError(null);
    setPreview({ item, uri });
  }

  useEffect(() => {
    mounted.current = true;
    setPreview(null);
    setQuery("");
    loadVault().catch(() => {});
    return () => {
      mounted.current = false;
      loadVersion.current += 1;
    };
  }, [ownerId]);

  useEffect(() => {
    setPreview(null);
    setPreviewError(null);
    setVisibleCount(INITIAL_VISIBLE_ITEMS);
  }, [kind]);

  useEffect(() => {
    setVisibleCount(INITIAL_VISIBLE_ITEMS);
  }, [query]);

  const filteredItems = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("pt-BR");
    return items.filter((item) => {
      if (item.kind !== kind) return false;
      return !normalized || item.name.toLocaleLowerCase("pt-BR").includes(normalized);
    });
  }, [items, kind, query]);

  const visibleItems = filteredItems.slice(0, visibleCount);
  const counts = useMemo(() => ({
    photo: items.filter((item) => item.kind === "PHOTO").length,
    video: items.filter((item) => item.kind === "VIDEO").length,
    bytes: items.reduce((total, item) => total + Math.max(0, item.size), 0)
  }), [items]);
  const storagePercent = Math.min(100, Math.max(0, (counts.bytes / VAULT_LIMIT_BYTES) * 100));

  return (
    <View style={s.root}>
      <View style={s.hero}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>{kind === "PHOTO" ? "Fotos" : "Vídeos"}</Text>
          <Text style={s.subtitle}>
            {kind === "PHOTO" ? counts.photo : counts.video} guardado(s) localmente • não sincronizado(s)
          </Text>
        </View>
        <Pressable
          style={[s.refresh, (busy || loading) && s.disabled]}
          disabled={busy || loading}
          onPress={() => { loadVault().catch(() => {}); }}
          accessibilityLabel="Atualizar mídia local"
        >
          <Text style={s.refreshText}>ATUALIZAR</Text>
        </Pressable>
      </View>

      <View style={s.privacyCard}>
        <Text style={s.privacyTitle}>LOCAL • NÃO ENVIADO AO SERVIDOR</Text>
        <Text style={s.privacyText}>
          Importar cria uma cópia no armazenamento privado do App 1. A mídia fica separada por instalação e perfil e não é publicada no Social.
        </Text>
      </View>

      <View style={s.storageCard}>
        <View style={s.storageRow}>
          <Text style={s.storageText}>{bytesLabel(counts.bytes)} usados</Text>
          <Text style={s.storageLimit}>limite total {bytesLabel(VAULT_LIMIT_BYTES)}</Text>
        </View>
        <View style={s.storageTrack}>
          <View style={[s.storageFill, { width: `${storagePercent}%` as `${number}%` }]} />
        </View>
        <Text style={s.itemLimit}>
          {kind === "PHOTO"
            ? `até ${bytesLabel(PHOTO_LIMIT_BYTES)} por foto`
            : `até ${bytesLabel(VIDEO_LIMIT_BYTES)} por vídeo`} • até {MAX_MEDIA_ITEMS} itens
        </Text>
      </View>

      <View style={s.searchRow}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          editable={!busy}
          style={s.search}
          placeholder={`Buscar ${kind === "PHOTO" ? "fotos" : "vídeos"}...`}
          placeholderTextColor="#66666E"
          autoCapitalize="none"
          autoCorrect={false}
        />
        <Pressable
          style={[s.importButton, (!base || busy || loading) && s.disabled]}
          disabled={!base || busy || loading}
          onPress={() => { importMedia().catch(() => {}); }}
          accessibilityLabel={`Importar ${kind === "PHOTO" ? "foto" : "vídeo"}`}
        >
          <Text style={s.importText}>{busy ? "..." : "IMPORTAR"}</Text>
        </Pressable>
      </View>

      {message ? <Text style={s.message}>{message}</Text> : null}
      {loading ? <ActivityIndicator style={{ marginVertical: 28 }} /> : null}

      {!loading && filteredItems.length === 0 ? (
        <View style={s.empty}>
          <Text style={s.emptyIcon}>{kind === "PHOTO" ? "FOTO" : "VÍDEO"}</Text>
          <Text style={s.emptyTitle}>Nenhum {kind === "PHOTO" ? "foto" : "vídeo"} guardado</Text>
          <Text style={s.emptyText}>
            Use IMPORTAR para selecionar um arquivo do celular e criar uma cópia privada dentro do App 1.
          </Text>
        </View>
      ) : null}

      {!loading ? visibleItems.map((item) => {
        const uri = base ? `${base}${item.fileName}` : "";
        const broken = brokenIds.includes(item.id);
        return (
          <View key={item.id} style={s.card}>
            {item.kind === "PHOTO" && uri && !broken ? (
              <Pressable onPress={() => { openPreview(item).catch(() => {}); }} accessibilityLabel={`Abrir ${item.name}`}>
                <Image
                  source={{ uri }}
                  style={s.photo}
                  resizeMode="cover"
                  onError={() => setBrokenIds((current) => current.includes(item.id) ? current : [...current, item.id])}
                />
              </Pressable>
            ) : (
              <Pressable
                style={[s.videoThumb, broken && s.brokenThumb]}
                onPress={() => { openPreview(item).catch(() => {}); }}
                accessibilityLabel={`Abrir ${item.name}`}
              >
                <Text style={s.videoGlyph}>{broken ? "ERRO" : item.kind === "VIDEO" ? "VÍDEO" : "FOTO"}</Text>
                <Text style={s.videoLabel}>{broken ? "ARQUIVO ILEGÍVEL" : item.kind === "VIDEO" ? "VÍDEO LOCAL" : "FOTO LOCAL"}</Text>
              </Pressable>
            )}
            <View style={s.cardBody}>
              <Text numberOfLines={2} style={s.name}>{item.name}</Text>
              <Text style={s.meta}>{bytesLabel(item.size)} • {dateText(item.importedAt)}</Text>
              {item.mimeType ? <Text style={s.mime}>{item.mimeType}</Text> : null}
              <View style={s.actions}>
                <Pressable
                  style={s.openButton}
                  disabled={busy}
                  onPress={() => { openPreview(item).catch(() => {}); }}
                >
                  <Text style={s.openText}>ABRIR</Text>
                </Pressable>
                <Pressable style={[s.delete, busy && s.disabled]} disabled={busy} onPress={() => confirmDelete(item)}>
                  <Text style={s.deleteText}>APAGAR</Text>
                </Pressable>
              </View>
            </View>
          </View>
        );
      }) : null}

      {!loading && visibleItems.length < filteredItems.length ? (
        <Pressable style={s.loadMore} disabled={busy} onPress={() => setVisibleCount((current) => current + INITIAL_VISIBLE_ITEMS)}>
          <Text style={s.loadMoreText}>CARREGAR MAIS • {filteredItems.length - visibleItems.length} RESTANTE(S)</Text>
        </Pressable>
      ) : null}

      <View style={s.note}>
        <Text style={s.noteTitle}>{kind === "PHOTO" ? "Visualização local" : "Player de vídeo local"}</Text>
        <Text style={s.noteText}>
          {kind === "PHOTO"
            ? "Toque na miniatura ou em ABRIR para visualizar a foto sem enviá-la pela internet."
            : "Toque em ABRIR para reproduzir com controles nativos e opção de tela cheia. A compatibilidade de formatos depende do aparelho."}
        </Text>
      </View>

      <Modal
        visible={Boolean(preview)}
        transparent
        animationType="fade"
        onRequestClose={() => !busy && setPreview(null)}
      >
        <View style={s.previewBackdrop}>
          <View style={s.previewPanel}>
            <View style={s.previewHeader}>
              <View style={{ flex: 1 }}>
                <Text style={s.previewEyebrow}>{preview?.item.kind === "PHOTO" ? "FOTO LOCAL" : "VÍDEO LOCAL"}</Text>
                <Text numberOfLines={2} style={s.previewTitle}>{preview?.item.name || "Mídia"}</Text>
              </View>
              <Pressable disabled={busy} onPress={() => setPreview(null)} accessibilityLabel="Fechar visualização">
                <Text style={s.previewClose}>FECHAR</Text>
              </Pressable>
            </View>

            <View style={s.previewMedia}>
              {preview?.item.kind === "PHOTO" ? (
                <Image
                  source={{ uri: preview.uri }}
                  style={s.previewImage}
                  resizeMode="contain"
                  onError={() => setPreviewError("Não foi possível abrir esta foto. O arquivo pode estar corrompido ou usar um formato não reconhecido.")}
                />
              ) : preview ? (
                <LocalVideoPreview uri={preview.uri} />
              ) : null}
            </View>

            {previewError ? <Text style={s.previewError}>{previewError}</Text> : null}
            {preview ? (
              <View style={s.previewFooter}>
                <Text style={s.previewMeta}>{bytesLabel(preview.item.size)} • importado {dateText(preview.item.importedAt)}</Text>
                <View style={s.previewActions}>
                  <Pressable style={s.previewDone} disabled={busy} onPress={() => setPreview(null)}>
                    <Text style={s.previewDoneText}>FECHAR</Text>
                  </Pressable>
                  <Pressable style={s.previewDelete} disabled={busy} onPress={() => confirmDelete(preview.item)}>
                    <Text style={s.previewDeleteText}>APAGAR CÓPIA</Text>
                  </Pressable>
                </View>
              </View>
            ) : null}
          </View>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, marginTop: 18 },
  hero: { flexDirection: "row", alignItems: "center", gap: 9 },
  title: { color: "#FFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.62)", fontSize: 10, lineHeight: 15, marginTop: 4 },
  refresh: { minWidth: 74, minHeight: 38, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(0,0,0,0.12)", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  refreshText: { color: "rgba(245,245,248,0.72)", fontSize: 7, fontWeight: "900" },
  privacyCard: { borderRadius: 14, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(5,5,7,0.18)", padding: 12, marginTop: 12 },
  privacyTitle: { color: "#FF8A91", fontSize: 8, fontWeight: "900", letterSpacing: 0.7 },
  privacyText: { color: "rgba(235,235,240,0.62)", fontSize: 9, lineHeight: 15, marginTop: 5 },
  storageCard: { borderRadius: 14, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(5,5,7,0.16)", padding: 12, marginTop: 10 },
  storageRow: { flexDirection: "row", justifyContent: "space-between", gap: 8 },
  storageText: { color: "rgba(245,245,248,0.80)", fontSize: 9, fontWeight: "800" },
  storageLimit: { color: "rgba(225,225,232,0.54)", fontSize: 8 },
  storageTrack: { height: 5, borderRadius: 999, backgroundColor: "rgba(255,255,255,0.10)", overflow: "hidden", marginTop: 8 },
  storageFill: { height: "100%", minWidth: 2, borderRadius: 999, backgroundColor: "#C92D36" },
  itemLimit: { color: "rgba(225,225,232,0.54)", fontSize: 8, marginTop: 7 },
  searchRow: { flexDirection: "row", gap: 8, marginTop: 10 },
  search: { flex: 1, minHeight: 47, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(0,0,0,0.20)", color: "#FFF", paddingHorizontal: 12 },
  importButton: { minWidth: 104, minHeight: 47, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,105,111,0.58)", backgroundColor: "rgba(181,29,37,0.88)", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  importText: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  message: { color: "rgba(245,225,228,0.80)", fontSize: 9, lineHeight: 14, marginTop: 8 },
  empty: { borderRadius: 18, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(5,5,7,0.16)", padding: 25, alignItems: "center", marginTop: 14 },
  emptyIcon: { color: "#FF8A91", fontSize: 9, fontWeight: "900", letterSpacing: 1.2 },
  emptyTitle: { color: "#FFF", fontSize: 14, fontWeight: "900", marginTop: 8 },
  emptyText: { color: "rgba(235,235,240,0.62)", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 6 },
  card: { flexDirection: "row", borderRadius: 16, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(5,5,7,0.16)", overflow: "hidden", marginTop: 10, minHeight: 118 },
  photo: { width: 118, height: 118, backgroundColor: "rgba(0,0,0,0.24)" },
  videoThumb: { width: 118, minHeight: 118, backgroundColor: "rgba(0,0,0,0.24)", alignItems: "center", justifyContent: "center", padding: 8 },
  brokenThumb: { backgroundColor: "rgba(82,12,17,0.28)" },
  videoGlyph: { color: "#FF8A91", fontSize: 9, fontWeight: "900", letterSpacing: 1 },
  videoLabel: { color: "rgba(235,235,240,0.58)", fontSize: 7, fontWeight: "900", marginTop: 5, textAlign: "center" },
  cardBody: { flex: 1, padding: 12 },
  name: { color: "#FFF", fontSize: 12, fontWeight: "900", lineHeight: 17 },
  meta: { color: "rgba(225,225,232,0.56)", fontSize: 8, marginTop: 5 },
  mime: { color: "rgba(225,225,232,0.44)", fontSize: 7, marginTop: 3 },
  actions: { flexDirection: "row", gap: 7, marginTop: "auto", paddingTop: 10 },
  openButton: { flex: 1, borderRadius: 8, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(0,0,0,0.12)", paddingHorizontal: 9, paddingVertical: 7, alignItems: "center" },
  openText: { color: "rgba(245,245,248,0.80)", fontSize: 7, fontWeight: "900" },
  delete: { borderRadius: 8, borderWidth: 1, borderColor: "rgba(211,71,83,0.50)", backgroundColor: "rgba(82,12,17,0.22)", paddingHorizontal: 9, paddingVertical: 7 },
  deleteText: { color: "#FF858B", fontSize: 7, fontWeight: "900" },
  loadMore: { minHeight: 48, marginTop: 12, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(0,0,0,0.10)", alignItems: "center", justifyContent: "center" },
  loadMoreText: { color: "rgba(245,245,248,0.74)", fontSize: 8, fontWeight: "900" },
  note: { borderRadius: 14, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(5,5,7,0.14)", padding: 12, marginTop: 14 },
  noteTitle: { color: "#FFF", fontSize: 10, fontWeight: "900" },
  noteText: { color: "rgba(235,235,240,0.58)", fontSize: 9, lineHeight: 15, marginTop: 5 },
  previewBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.72)", alignItems: "center", justifyContent: "center", padding: 12 },
  previewPanel: { width: "100%", maxWidth: 760, height: "90%", borderRadius: 20, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(7,7,9,0.80)", padding: 12 },
  previewHeader: { flexDirection: "row", alignItems: "flex-start", gap: 10, paddingBottom: 10 },
  previewEyebrow: { color: "#FF7E86", fontSize: 8, fontWeight: "900", letterSpacing: 1.1 },
  previewTitle: { color: "#FFF", fontSize: 15, lineHeight: 20, fontWeight: "900", marginTop: 4 },
  previewClose: { color: "rgba(245,245,248,0.72)", fontSize: 8, fontWeight: "900", paddingHorizontal: 6, paddingVertical: 7 },
  previewMedia: { flex: 1, minHeight: 180, borderRadius: 14, overflow: "hidden", backgroundColor: "#000" },
  previewImage: { width: "100%", height: "100%" },
  previewError: { color: "#FF858A", fontSize: 10, lineHeight: 15, marginTop: 8 },
  previewFooter: { paddingTop: 10 },
  previewMeta: { color: "rgba(225,225,232,0.54)", fontSize: 8 },
  previewActions: { flexDirection: "row", gap: 8, marginTop: 8 },
  previewDone: { flex: 1, minHeight: 44, borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(0,0,0,0.14)", alignItems: "center", justifyContent: "center" },
  previewDoneText: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  previewDelete: { minHeight: 44, borderRadius: 11, borderWidth: 1, borderColor: "rgba(211,71,83,0.52)", backgroundColor: "rgba(82,12,17,0.24)", paddingHorizontal: 14, alignItems: "center", justifyContent: "center" },
  previewDeleteText: { color: "#FF858B", fontSize: 8, fontWeight: "900" },
  videoPreviewRoot: { flex: 1, position: "relative", backgroundColor: "#000" },
  videoPlayer: { width: "100%", height: "100%" },
  playerOverlay: { ...StyleSheet.absoluteFill, alignItems: "center", justifyContent: "center", gap: 8, backgroundColor: "rgba(0,0,0,0.32)" },
  playerOverlayText: { color: "#C9C9CE", fontSize: 9 },
  playerError: { ...StyleSheet.absoluteFill, alignItems: "center", justifyContent: "center", backgroundColor: "rgba(48,7,10,0.78)", padding: 24 },
  playerErrorTitle: { color: "#FF858A", fontSize: 13, fontWeight: "900", textAlign: "center" },
  playerErrorText: { color: "rgba(235,190,195,0.72)", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 7 },
  disabled: { opacity: 0.42 }
});