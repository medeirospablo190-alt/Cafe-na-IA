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
import * as Crypto from "expo-crypto";
import * as FileSystem from "expo-file-system/legacy";
import { getApp1InstallationId } from "./device";
import { LocalMediaVault as LocalMediaVaultCore } from "./LocalMediaVaultCore";

export type MediaKind = "PHOTO" | "VIDEO";

type IndexedItem = {
  id: string;
  kind: MediaKind;
  name: string;
  fileName: string;
};

type VaultDocument = {
  version?: unknown;
  items: unknown[];
  [key: string]: unknown;
};

const METADATA_FILE = "vault.json";
const METADATA_TEMP_FILE = "vault.json.tmp";
const METADATA_BACKUP_FILE = "vault.json.bak";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TRASH_RE = /^\.trash-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})-(\d+)$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object";
}

function infoExists(value: unknown) {
  return isRecord(value) && value.exists === true;
}

function safeName(value: string, fallback: string) {
  const cleaned = String(value || "")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .slice(0, 120);
  return cleaned || fallback;
}

function safeIndexedItem(value: unknown): IndexedItem | null {
  if (!isRecord(value)) return null;
  const id = typeof value.id === "string" ? value.id.trim() : "";
  const kind = value.kind;
  const fileName = typeof value.fileName === "string" ? value.fileName.trim() : "";
  if (!UUID_RE.test(id) || (kind !== "PHOTO" && kind !== "VIDEO")) return null;
  const escapedId = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (!new RegExp(`^${escapedId}\\.[a-zA-Z0-9]{1,8}$`).test(fileName)) return null;
  return {
    id,
    kind,
    fileName,
    name: safeName(typeof value.name === "string" ? value.name : "", kind === "PHOTO" ? "Foto" : "Vídeo")
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

async function resolveBase(ownerId: string) {
  const root = FileSystem.documentDirectory;
  if (!root) throw new Error("O armazenamento interno do aplicativo não está disponível neste aparelho.");
  const namespace = await namespaceForOwner(ownerId);
  const base = `${root}grupo-lua-media/${namespace}/`;
  await FileSystem.makeDirectoryAsync(base, { intermediates: true });
  return base;
}

async function readVaultDocument(uri: string): Promise<VaultDocument | null> {
  const info = await FileSystem.getInfoAsync(uri).catch(() => null);
  if (!infoExists(info)) return null;
  const raw = await FileSystem.readAsStringAsync(uri, { encoding: FileSystem.EncodingType.UTF8 });
  const parsed: unknown = JSON.parse(raw);
  if (!isRecord(parsed) || !Array.isArray(parsed.items)) return null;
  return parsed as VaultDocument;
}

async function readBestVaultDocument(base: string) {
  const candidates = [METADATA_FILE, METADATA_TEMP_FILE, METADATA_BACKUP_FILE];
  for (const file of candidates) {
    try {
      const document = await readVaultDocument(`${base}${file}`);
      if (document) return document;
    } catch {
      // O núcleo do cofre fará a recuperação completa do índice depois desta camada.
    }
  }
  return null;
}

async function writeVaultDocument(base: string, document: VaultDocument) {
  const primary = `${base}${METADATA_FILE}`;
  const temporary = `${base}${METADATA_TEMP_FILE}`;
  const backup = `${base}${METADATA_BACKUP_FILE}`;
  await FileSystem.writeAsStringAsync(temporary, JSON.stringify(document), {
    encoding: FileSystem.EncodingType.UTF8
  });

  const primaryInfo = await FileSystem.getInfoAsync(primary).catch(() => null);
  if (infoExists(primaryInfo)) {
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

async function reconcileInterruptedDeletes(base: string) {
  const document = await readBestVaultDocument(base);
  const indexed = new Map<string, IndexedItem>();
  for (const value of document?.items || []) {
    const item = safeIndexedItem(value);
    if (item) indexed.set(item.id, item);
  }

  const entries = await FileSystem.readDirectoryAsync(base).catch(() => [] as string[]);
  let restored = 0;
  let cleaned = 0;

  for (const entry of entries) {
    const match = TRASH_RE.exec(entry);
    if (!match) continue;
    const trash = `${base}${entry}`;
    const item = indexed.get(match[1]);
    if (!item) {
      await FileSystem.deleteAsync(trash, { idempotent: true }).catch(() => {});
      cleaned += 1;
      continue;
    }

    const source = `${base}${item.fileName}`;
    const sourceInfo = await FileSystem.getInfoAsync(source).catch(() => null);
    if (infoExists(sourceInfo)) {
      await FileSystem.deleteAsync(trash, { idempotent: true }).catch(() => {});
      cleaned += 1;
      continue;
    }

    try {
      await FileSystem.moveAsync({ from: trash, to: source });
      restored += 1;
    } catch {
      // Se a restauração falhar, deixamos a lixeira intacta para uma próxima abertura.
    }
  }

  return { restored, cleaned };
}

async function loadIndexedItems(base: string) {
  const document = await readBestVaultDocument(base);
  if (!document) return [] as IndexedItem[];
  const items: IndexedItem[] = [];
  const seen = new Set<string>();
  for (const raw of document.items) {
    const item = safeIndexedItem(raw);
    if (!item || seen.has(item.id)) continue;
    seen.add(item.id);
    items.push(item);
  }
  return items;
}

async function renameIndexedItem(base: string, id: string, name: string) {
  const document = await readBestVaultDocument(base);
  if (!document) throw new Error("O índice local de mídia não está disponível.");
  const cleaned = safeName(name, "");
  if (!cleaned) throw new Error("Digite um nome para a mídia.");

  let found = false;
  const nextItems = document.items.map((raw) => {
    if (!isRecord(raw) || raw.id !== id) return raw;
    found = true;
    return { ...raw, name: cleaned };
  });
  if (!found) throw new Error("Esta mídia não existe mais no índice local.");
  await writeVaultDocument(base, { ...document, items: nextItems });
  return cleaned;
}

export function LocalMediaVault({ kind, ownerId }: { kind: MediaKind; ownerId: string }) {
  const [preparing, setPreparing] = useState(true);
  const [base, setBase] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const [recoveryMessage, setRecoveryMessage] = useState<string | null>(null);
  const [managerOpen, setManagerOpen] = useState(false);
  const [managerItems, setManagerItems] = useState<IndexedItem[]>([]);
  const [managerBusy, setManagerBusy] = useState(false);
  const [renameTarget, setRenameTarget] = useState<IndexedItem | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    let active = true;
    setPreparing(true);
    setBase(null);
    setRecoveryMessage(null);
    setManagerOpen(false);
    setRenameTarget(null);

    (async () => {
      try {
        const directory = await resolveBase(ownerId);
        const result = await reconcileInterruptedDeletes(directory);
        if (!active || !mounted.current) return;
        setBase(directory);
        if (result.restored || result.cleaned) {
          const parts: string[] = [];
          if (result.restored) parts.push(`${result.restored} exclusão(ões) interrompida(s) recuperada(s)`);
          if (result.cleaned) parts.push(`${result.cleaned} sobra(s) de exclusão limpa(s)`);
          setRecoveryMessage(`${parts.join(" • ")}.`);
        }
      } catch {
        // O núcleo ainda pode abrir e executar sua própria recuperação.
      } finally {
        if (active && mounted.current) setPreparing(false);
      }
    })().catch(() => {});

    return () => {
      active = false;
      mounted.current = false;
    };
  }, [ownerId]);

  const visibleManagerItems = useMemo(
    () => managerItems.filter((item) => item.kind === kind),
    [managerItems, kind]
  );

  async function openManager() {
    if (!base || managerBusy) return;
    setManagerBusy(true);
    try {
      setManagerItems(await loadIndexedItems(base));
      setManagerOpen(true);
    } catch (error) {
      Alert.alert("Organização indisponível", error instanceof Error ? error.message : "Não foi possível ler o índice local.");
    } finally {
      if (mounted.current) setManagerBusy(false);
    }
  }

  function beginRename(item: IndexedItem) {
    setRenameTarget(item);
    setRenameValue(item.name);
  }

  async function saveRename() {
    if (!base || !renameTarget || managerBusy) return;
    const nextName = safeName(renameValue, "");
    if (!nextName) {
      Alert.alert("Nome obrigatório", "Digite um nome para esta mídia.");
      return;
    }
    setManagerBusy(true);
    try {
      const saved = await renameIndexedItem(base, renameTarget.id, nextName);
      const refreshed = await loadIndexedItems(base);
      if (!mounted.current) return;
      setManagerItems(refreshed);
      setRenameTarget(null);
      setRenameValue("");
      setRevision((value) => value + 1);
      setRecoveryMessage(`${saved} foi renomeado no cofre local.`);
    } catch (error) {
      Alert.alert("Não foi possível renomear", error instanceof Error ? error.message : "Falha ao atualizar o nome.");
    } finally {
      if (mounted.current) setManagerBusy(false);
    }
  }

  if (preparing) {
    return (
      <View style={s.loadingCard}>
        <ActivityIndicator size="small" />
        <Text style={s.loadingText}>Verificando mídia local...</Text>
      </View>
    );
  }

  return (
    <View style={s.root}>
      <View style={s.organizerRow}>
        <View style={{ flex: 1 }}>
          <Text style={s.organizerTitle}>Cofre local protegido</Text>
          <Text style={s.organizerText}>Recuperação automática de exclusões interrompidas e nomes editáveis.</Text>
        </View>
        <Pressable
          style={[s.organizerButton, (!base || managerBusy) && s.disabled]}
          disabled={!base || managerBusy}
          onPress={() => { openManager().catch(() => {}); }}
        >
          <Text style={s.organizerButtonText}>{managerBusy ? "..." : "ORGANIZAR"}</Text>
        </Pressable>
      </View>

      {recoveryMessage ? <Text style={s.recoveryMessage}>{recoveryMessage}</Text> : null}

      <LocalMediaVaultCore key={`${ownerId}:${revision}`} kind={kind} ownerId={ownerId} />

      <Modal visible={managerOpen} transparent animationType="fade" onRequestClose={() => !managerBusy && setManagerOpen(false)}>
        <View style={s.modalBackdrop}>
          <View style={s.managerPanel}>
            <View style={s.modalHeader}>
              <View style={{ flex: 1 }}>
                <Text style={s.modalEyebrow}>ORGANIZAR {kind === "PHOTO" ? "FOTOS" : "VÍDEOS"}</Text>
                <Text style={s.modalTitle}>Nomes do cofre</Text>
              </View>
              <Pressable disabled={managerBusy} onPress={() => setManagerOpen(false)}>
                <Text style={s.close}>FECHAR</Text>
              </Pressable>
            </View>

            <ScrollView style={s.managerList} contentContainerStyle={s.managerListContent} keyboardShouldPersistTaps="handled">
              {visibleManagerItems.length === 0 ? (
                <Text style={s.empty}>Nenhuma mídia desta categoria para organizar.</Text>
              ) : visibleManagerItems.map((item) => (
                <View key={item.id} style={s.itemRow}>
                  <View style={{ flex: 1 }}>
                    <Text numberOfLines={2} style={s.itemName}>{item.name}</Text>
                    <Text style={s.itemMeta}>{item.kind === "PHOTO" ? "FOTO LOCAL" : "VÍDEO LOCAL"}</Text>
                  </View>
                  <Pressable style={s.renameButton} disabled={managerBusy} onPress={() => beginRename(item)}>
                    <Text style={s.renameButtonText}>RENOMEAR</Text>
                  </Pressable>
                </View>
              ))}
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(renameTarget)} transparent animationType="fade" onRequestClose={() => !managerBusy && setRenameTarget(null)}>
        <KeyboardAvoidingView
          style={s.modalBackdrop}
          behavior={Platform.OS === "ios" ? "padding" : "height"}
        >
          <View style={s.renamePanel}>
            <Text style={s.modalEyebrow}>NOME LOCAL</Text>
            <Text style={s.modalTitle}>Renomear mídia</Text>
            <TextInput
              value={renameValue}
              onChangeText={(value) => setRenameValue(Array.from(value).slice(0, 120).join(""))}
              editable={!managerBusy}
              maxLength={120}
              autoCorrect={false}
              style={s.input}
              placeholder="Nome da mídia"
              placeholderTextColor="#686870"
              selectTextOnFocus
            />
            <Text style={s.counter}>{Array.from(renameValue).length}/120</Text>
            <Pressable style={[s.saveButton, managerBusy && s.disabled]} disabled={managerBusy} onPress={() => { saveRename().catch(() => {}); }}>
              <Text style={s.saveButtonText}>{managerBusy ? "SALVANDO..." : "SALVAR NOME"}</Text>
            </Pressable>
            <Pressable style={s.cancelButton} disabled={managerBusy} onPress={() => setRenameTarget(null)}>
              <Text style={s.cancelButtonText}>CANCELAR</Text>
            </Pressable>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  loadingCard: { minHeight: 110, borderRadius: 16, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(5,5,7,0.18)", alignItems: "center", justifyContent: "center", gap: 8, marginTop: 18 },
  loadingText: { color: "rgba(235,235,240,0.64)", fontSize: 9 },
  organizerRow: { flexDirection: "row", alignItems: "center", gap: 10, borderRadius: 14, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(5,5,7,0.18)", padding: 11, marginTop: 18 },
  organizerTitle: { color: "#FFF", fontSize: 10, fontWeight: "900" },
  organizerText: { color: "rgba(235,235,240,0.62)", fontSize: 8, lineHeight: 13, marginTop: 3 },
  organizerButton: { minHeight: 38, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,105,111,0.58)", backgroundColor: "rgba(95,15,20,0.30)", alignItems: "center", justifyContent: "center", paddingHorizontal: 11 },
  organizerButtonText: { color: "#FF9299", fontSize: 8, fontWeight: "900" },
  recoveryMessage: { color: "rgba(245,225,228,0.78)", fontSize: 8, lineHeight: 13, marginTop: 7, paddingHorizontal: 3 },
  disabled: { opacity: 0.45 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.58)", alignItems: "center", justifyContent: "center", padding: 16 },
  managerPanel: { width: "100%", maxWidth: 540, maxHeight: "78%", borderRadius: 18, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(7,7,10,0.76)", padding: 15 },
  renamePanel: { width: "100%", maxWidth: 480, borderRadius: 18, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(7,7,10,0.76)", padding: 16 },
  modalHeader: { flexDirection: "row", alignItems: "center", gap: 10 },
  modalEyebrow: { color: "#FF727D", fontSize: 8, fontWeight: "900", letterSpacing: 1 },
  modalTitle: { color: "#FFF", fontSize: 19, fontWeight: "900", marginTop: 4 },
  close: { color: "rgba(245,245,248,0.72)", fontSize: 8, fontWeight: "900", paddingHorizontal: 7, paddingVertical: 9 },
  managerList: { marginTop: 12 },
  managerListContent: { paddingBottom: 4 },
  empty: { color: "rgba(235,235,240,0.62)", fontSize: 10, textAlign: "center", paddingVertical: 24 },
  itemRow: { flexDirection: "row", alignItems: "center", gap: 10, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(0,0,0,0.16)", padding: 11, marginBottom: 7 },
  itemName: { color: "#FFF", fontSize: 10, fontWeight: "800" },
  itemMeta: { color: "rgba(225,225,232,0.56)", fontSize: 7, fontWeight: "900", marginTop: 4 },
  renameButton: { minHeight: 34, borderRadius: 9, borderWidth: 1, borderColor: "rgba(211,71,83,0.52)", backgroundColor: "rgba(72,10,15,0.22)", paddingHorizontal: 9, alignItems: "center", justifyContent: "center" },
  renameButtonText: { color: "#FF9098", fontSize: 7, fontWeight: "900" },
  input: { minHeight: 50, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.16)", backgroundColor: "rgba(0,0,0,0.24)", color: "#FFF", paddingHorizontal: 12, marginTop: 13 },
  counter: { color: "rgba(225,225,232,0.54)", fontSize: 8, textAlign: "right", marginTop: 4 },
  saveButton: { minHeight: 48, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,105,111,0.58)", backgroundColor: "rgba(181,29,37,0.90)", alignItems: "center", justifyContent: "center", marginTop: 11 },
  saveButtonText: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  cancelButton: { minHeight: 42, alignItems: "center", justifyContent: "center", marginTop: 3 },
  cancelButtonText: { color: "rgba(240,240,245,0.68)", fontSize: 8, fontWeight: "900" }
});