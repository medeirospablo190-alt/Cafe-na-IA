import { useMemo, useState } from "react";
import {
  Alert,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";
import { createLibraryItem, type LibraryKind } from "./api";

type ImportDraft = {
  kind: LibraryKind;
  title: string;
  content: string;
  sourceName: string;
};

const TITLE_MAX = 120;
const MAX_CODE_BYTES = 1_000_000;
const MAX_LOADSTRING_CHARS = 32_768;
const ALLOWED_EXTENSIONS = new Set([".lua", ".luau", ".txt"]);

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

function fileExtension(name: string) {
  const match = String(name || "").trim().match(/(\.[a-zA-Z0-9]+)$/);
  return match ? match[1].toLowerCase() : "";
}

function titleFromFileName(name: string) {
  const extension = fileExtension(name);
  const withoutExtension = extension ? name.slice(0, -extension.length) : name;
  return withoutExtension
    .normalize("NFKC")
    .replace(/[\u0000-\u001f]/g, "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, TITLE_MAX) || "Arquivo importado";
}

function bytesLabel(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

async function cleanupPickerCopy(uri: string | null) {
  const cache = FileSystem.cacheDirectory;
  if (!uri || !cache || !uri.startsWith(cache)) return;
  await FileSystem.deleteAsync(uri, { idempotent: true }).catch(() => {});
}

export function TextFileImporter({
  sessionToken,
  deviceToken,
  onSaved
}: {
  sessionToken: string;
  deviceToken: string;
  onSaved: () => void;
}) {
  const [draft, setDraft] = useState<ImportDraft | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const draftBytes = useMemo(() => draft ? utf8ByteLength(draft.content) : 0, [draft?.content]);
  const draftChars = useMemo(() => draft ? codePointLength(draft.content) : 0, [draft?.content]);
  const draftTooLarge = Boolean(draft && (
    draft.kind === "LOADSTRING"
      ? draftChars > MAX_LOADSTRING_CHARS
      : draftBytes > MAX_CODE_BYTES
  ));

  async function pickFile(kind: LibraryKind) {
    if (busy) return;
    setBusy(true);
    setMessage(null);
    let pickedUri: string | null = null;

    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: "*/*",
        copyToCacheDirectory: true,
        multiple: false
      });
      if (result.canceled || !result.assets?.[0]) return;

      const asset = result.assets[0];
      pickedUri = asset.uri;
      const sourceName = String(asset.name || "").trim();
      const extension = fileExtension(sourceName);
      if (!ALLOWED_EXTENSIONS.has(extension)) {
        throw new Error("Selecione um arquivo .lua, .luau ou .txt.");
      }

      const info = await FileSystem.getInfoAsync(asset.uri).catch(() => null);
      const knownSize = info && typeof info === "object" && "exists" in info && info.exists === true && "size" in info && typeof info.size === "number"
        ? info.size
        : typeof asset.size === "number"
          ? asset.size
          : 0;
      if (knownSize > MAX_CODE_BYTES) {
        throw new Error(`O arquivo ultrapassa o limite de ${bytesLabel(MAX_CODE_BYTES)}.`);
      }

      let content = await FileSystem.readAsStringAsync(asset.uri, {
        encoding: FileSystem.EncodingType.UTF8
      });
      if (content.charCodeAt(0) === 0xfeff) content = content.slice(1);
      if (!content.trim()) throw new Error("O arquivo selecionado está vazio.");

      const bytes = utf8ByteLength(content);
      if (bytes > MAX_CODE_BYTES) {
        throw new Error(`O conteúdo ultrapassa o limite de ${bytesLabel(MAX_CODE_BYTES)}.`);
      }
      if (kind === "LOADSTRING" && codePointLength(content) > MAX_LOADSTRING_CHARS) {
        throw new Error(
          `A loadstring ultrapassa ${MAX_LOADSTRING_CHARS.toLocaleString("pt-BR")} caracteres.`
        );
      }

      setDraft({
        kind,
        title: titleFromFileName(sourceName),
        content,
        sourceName
      });
    } catch (error) {
      Alert.alert(
        "Não foi possível importar",
        error instanceof Error ? error.message : "Falha ao ler o arquivo selecionado."
      );
    } finally {
      await cleanupPickerCopy(pickedUri);
      setBusy(false);
    }
  }

  function chooseKind() {
    if (busy) return;
    Alert.alert(
      "Importar arquivo",
      "Como este arquivo deve ser salvo na biblioteca?",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Código", onPress: () => { pickFile("CODE").catch(() => {}); } },
        { text: "Loadstring", onPress: () => { pickFile("LOADSTRING").catch(() => {}); } }
      ]
    );
  }

  async function saveDraft() {
    if (!draft || busy) return;
    const title = draft.title
      .normalize("NFKC")
      .replace(/[\u0000-\u001f]/g, "")
      .trim()
      .replace(/\s+/g, " ")
      .slice(0, TITLE_MAX);
    if (!title) {
      Alert.alert("Nome obrigatório", "Dê um nome ao arquivo antes de salvar.");
      return;
    }
    if (!draft.content.trim()) {
      Alert.alert("Conteúdo vazio", "O conteúdo não pode ficar vazio.");
      return;
    }
    if (draftTooLarge) {
      Alert.alert(
        "Conteúdo muito grande",
        draft.kind === "LOADSTRING"
          ? `O limite é ${MAX_LOADSTRING_CHARS.toLocaleString("pt-BR")} caracteres por loadstring.`
          : `O limite é ${bytesLabel(MAX_CODE_BYTES)} por código.`
      );
      return;
    }

    setBusy(true);
    try {
      await createLibraryItem(sessionToken, deviceToken, {
        kind: draft.kind,
        title,
        content: draft.content
      });
      const kind = draft.kind;
      setDraft(null);
      setMessage(`${title} importado como ${kind === "LOADSTRING" ? "loadstring" : "código"} e salvo no servidor.`);
      onSaved();
    } catch (error) {
      Alert.alert(
        "Não foi possível salvar",
        error instanceof Error ? error.message : "Erro desconhecido."
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <View style={s.importStrip}>
        <View style={{ flex: 1 }}>
          <Text style={s.importTitle}>Importar script</Text>
          <Text style={s.importHint}>.lua • .luau • .txt — só envia depois de SALVAR</Text>
        </View>
        <Pressable
          style={[s.importButton, busy && s.disabled]}
          disabled={busy}
          onPress={chooseKind}
          accessibilityLabel="Importar arquivo Lua, Luau ou texto"
        >
          <Text style={s.importButtonText}>{busy ? "..." : "IMPORTAR"}</Text>
        </Pressable>
      </View>

      {message ? <Text style={s.message}>{message}</Text> : null}

      <Modal
        visible={Boolean(draft)}
        transparent
        animationType="slide"
        onRequestClose={() => !busy && setDraft(null)}
      >
        <KeyboardAvoidingView
          style={s.modalKeyboard}
          behavior={Platform.OS === "ios" ? "padding" : "height"}
        >
          <View style={s.modalBackdrop}>
            <View style={s.modalPanel}>
              <View style={s.modalHeader}>
                <View style={{ flex: 1 }}>
                  <Text style={s.modalEyebrow}>ARQUIVO IMPORTADO</Text>
                  <Text style={s.modalTitle}>
                    {draft?.kind === "LOADSTRING" ? "Revisar loadstring" : "Revisar código"}
                  </Text>
                  <Text numberOfLines={1} style={s.sourceName}>{draft?.sourceName}</Text>
                </View>
                <Pressable
                  disabled={busy}
                  onPress={() => setDraft(null)}
                  accessibilityLabel="Fechar importação"
                >
                  <Text style={s.close}>FECHAR</Text>
                </Pressable>
              </View>

              {draft ? (
                <>
                  <TextInput
                    value={draft.title}
                    onChangeText={(title) => setDraft({ ...draft, title })}
                    style={s.input}
                    placeholder="Nome do arquivo"
                    placeholderTextColor="#626268"
                    maxLength={TITLE_MAX}
                    editable={!busy}
                  />
                  <TextInput
                    value={draft.content}
                    onChangeText={(content) => setDraft({ ...draft, content })}
                    style={s.codeInput}
                    placeholder="Conteúdo do arquivo"
                    placeholderTextColor="#55555C"
                    multiline
                    scrollEnabled
                    textAlignVertical="top"
                    autoCapitalize="none"
                    autoCorrect={false}
                    editable={!busy}
                  />
                  <Text style={[s.counter, draftTooLarge && s.counterDanger]}>
                    {draft.kind === "LOADSTRING"
                      ? `${draftChars.toLocaleString("pt-BR")} / ${MAX_LOADSTRING_CHARS.toLocaleString("pt-BR")} caracteres`
                      : `${bytesLabel(draftBytes)} / ${bytesLabel(MAX_CODE_BYTES)}`}
                  </Text>

                  <View style={s.actions}>
                    <Pressable
                      style={s.cancelButton}
                      disabled={busy}
                      onPress={() => setDraft(null)}
                    >
                      <Text style={s.cancelText}>CANCELAR</Text>
                    </Pressable>
                    <Pressable
                      style={[s.saveButton, (busy || draftTooLarge) && s.disabled]}
                      disabled={busy || draftTooLarge}
                      onPress={() => { saveDraft().catch(() => {}); }}
                    >
                      <Text style={s.saveButtonText}>{busy ? "SALVANDO..." : "SALVAR NO SERVIDOR"}</Text>
                    </Pressable>
                  </View>
                </>
              ) : null}
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </>
  );
}

const s = StyleSheet.create({
  importStrip: {
    minHeight: 52,
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.18)",
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginBottom: 8
  },
  importTitle: { color: "#FFFFFF", fontSize: 12, fontWeight: "900" },
  importHint: { color: "rgba(235,235,240,0.60)", fontSize: 10, marginTop: 2 },
  importButton: {
    minHeight: 44,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: "rgba(255,105,111,0.58)",
    backgroundColor: "rgba(95,15,20,0.30)",
    paddingHorizontal: 14,
    alignItems: "center",
    justifyContent: "center"
  },
  importButtonText: { color: "#FF9299", fontSize: 10, fontWeight: "900" },
  message: { color: "rgba(245,225,228,0.80)", fontSize: 10, marginBottom: 7 },
  modalKeyboard: { flex: 1 },
  modalBackdrop: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.58)",
    justifyContent: "flex-end"
  },
  modalPanel: {
    height: "86%",
    backgroundColor: "rgba(7,7,9,0.76)",
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    padding: 16
  },
  modalHeader: { flexDirection: "row", alignItems: "flex-start", gap: 10, paddingBottom: 12 },
  modalEyebrow: { color: "#FF7E86", fontSize: 9, fontWeight: "900", letterSpacing: 1.2 },
  modalTitle: { color: "#FFFFFF", fontSize: 21, fontWeight: "900", marginTop: 4 },
  sourceName: { color: "rgba(225,225,232,0.58)", fontSize: 10, marginTop: 4 },
  close: { color: "rgba(245,245,248,0.72)", fontSize: 8, fontWeight: "900", paddingHorizontal: 5, paddingVertical: 9 },
  input: {
    minHeight: 50,
    borderRadius: 13,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.22)",
    color: "#FFFFFF",
    paddingHorizontal: 14,
    fontSize: 15
  },
  codeInput: {
    flex: 1,
    minHeight: 220,
    marginTop: 10,
    borderRadius: 13,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.34)",
    color: "#E6E6EA",
    padding: 14,
    fontFamily: "monospace",
    fontSize: 12,
    lineHeight: 18
  },
  counter: { color: "rgba(225,225,232,0.56)", fontSize: 10, textAlign: "right", marginTop: 6 },
  counterDanger: { color: "#FF6258", fontWeight: "900" },
  actions: { flexDirection: "row", gap: 9, marginTop: 10 },
  cancelButton: {
    minHeight: 44,
    borderRadius: 13,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.12)",
    paddingHorizontal: 18,
    alignItems: "center",
    justifyContent: "center"
  },
  cancelText: { color: "rgba(240,240,245,0.72)", fontSize: 10, fontWeight: "900" },
  saveButton: {
    flex: 1,
    minHeight: 50,
    borderRadius: 13,
    borderWidth: 1,
    borderColor: "rgba(255,105,111,0.58)",
    backgroundColor: "rgba(181,29,37,0.90)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 14
  },
  saveButtonText: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  disabled: { opacity: 0.45 }
});