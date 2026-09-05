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
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";
import { App1ApiError } from "./api";
import { buildMenuLoader } from "./menuLoader";
import {
  type KeyKindFilter,
  type ManagedMenuV2,
  type MenuKeyKindV2,
  type MenuKeyV2,
  type MenuOrder,
  claimLegacyMenuV2,
  configureVipKeyV2,
  createManagedMenuV2,
  createMenuKeyV2,
  deleteManagedMenuV2,
  deleteMenuKeyV2,
  getManagedMenuSourceV2,
  listManagedMenusV2,
  listMenuKeysV2,
  releaseFreeKeyV2,
  resetMenuKeyDeviceV2,
  revealMenuKeyV2,
  setManagedMenuStateV2,
  updateManagedMenuV2
} from "./menu-admin-api-v2";

type SourceMode = "INLINE" | "URL";
type VipUnit = "DAYS" | "MONTHS" | "PERMANENT";

type RevealedSecret = {
  name: string;
  value: string;
};

const MAX_PRIVATE_LUA_BYTES = 4 * 1024 * 1024;
const ALLOWED_LUA_EXTENSIONS = new Set([".lua", ".luau"]);

function fileExtension(name: string) {
  const match = String(name || "").trim().match(/(\.[a-zA-Z0-9]+)$/);
  return match ? match[1].toLowerCase() : "";
}

async function cleanupPickerCopy(uri: string | null) {
  const cache = FileSystem.cacheDirectory;
  if (!uri || !cache || !uri.startsWith(cache)) return;
  await FileSystem.deleteAsync(uri, { idempotent: true }).catch(() => {});
}

function errorText(error: unknown) {
  if (error instanceof App1ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return "Não foi possível concluir esta operação.";
}

function positiveInteger(value: string) {
  const numeric = Math.floor(Number(value.trim()));
  return Number.isFinite(numeric) && numeric >= 1 ? numeric : null;
}

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function durationText(key: MenuKeyV2) {
  if (key.kind === "FREE") return `${key.duration_value || 24}h por ciclo`;
  if (key.duration_unit === "PERMANENT") return "Permanente";
  if (key.duration_unit === "MONTHS") return `${key.duration_value || 1} mês(es)`;
  return `${key.duration_value || 1} dia(s)`;
}

function keyStateText(key: MenuKeyV2) {
  if (key.access_state === "WAITING_ADMIN") return "AGUARDA ADM";
  if (key.access_state === "EXPIRED") return "EXPIRADA";
  if (key.access_state === "ACTIVE") return "EM USO";
  return "PRONTA";
}

function sourceLabel(menu: ManagedMenuV2) {
  return menu.source_kind === "INLINE_ENCRYPTED" ? "LUA PRIVADO" : "GITHUB LUA";
}

export function KeysScreenV2({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [menus, setMenus] = useState<ManagedMenuV2[]>([]);
  const [menusLoading, setMenusLoading] = useState(true);
  const [menuQuery, setMenuQuery] = useState("");
  const [menuStatus, setMenuStatus] = useState<"" | "ACTIVE" | "SUSPENDED">("");
  const [menuOrder, setMenuOrder] = useState<MenuOrder>("RECENT");
  const [selectedMenu, setSelectedMenu] = useState<ManagedMenuV2 | null>(null);

  const [keys, setKeys] = useState<MenuKeyV2[]>([]);
  const [keysLoading, setKeysLoading] = useState(false);
  const [keyQuery, setKeyQuery] = useState("");
  const [keyKind, setKeyKind] = useState<KeyKindFilter>("ALL");
  const [keyOrder, setKeyOrder] = useState<MenuOrder>("RECENT");

  const [busy, setBusy] = useState(false);
  const actionLock = useRef(false);
  const menuRequest = useRef(0);
  const keyRequest = useRef(0);

  const [menuEditorOpen, setMenuEditorOpen] = useState(false);
  const [menuEditorTarget, setMenuEditorTarget] = useState<ManagedMenuV2 | null>(null);
  const [menuName, setMenuName] = useState("");
  const [sourceMode, setSourceMode] = useState<SourceMode>("INLINE");
  const [sourceCode, setSourceCode] = useState("");
  const [sourceUrl, setSourceUrl] = useState("");
  const [sourceLoading, setSourceLoading] = useState(false);

  const [suspendTarget, setSuspendTarget] = useState<ManagedMenuV2 | null>(null);
  const [suspendMinutes, setSuspendMinutes] = useState("");

  const [keyEditorOpen, setKeyEditorOpen] = useState(false);
  const [keyName, setKeyName] = useState("");
  const [newKeyKind, setNewKeyKind] = useState<MenuKeyKindV2>("FREE");
  const [keyDuration, setKeyDuration] = useState("24");
  const [keyVipUnit, setKeyVipUnit] = useState<VipUnit>("DAYS");
  const [keyNote, setKeyNote] = useState("");

  const [renewTarget, setRenewTarget] = useState<MenuKeyV2 | null>(null);
  const [renewDuration, setRenewDuration] = useState("24");
  const [renewVipUnit, setRenewVipUnit] = useState<VipUnit>("DAYS");
  const [revealed, setRevealed] = useState<RevealedSecret | null>(null);

  async function runLocked(action: () => Promise<void>, title = "Falha") {
    if (actionLock.current) return;
    actionLock.current = true;
    setBusy(true);
    try {
      await action();
    } catch (error) {
      Alert.alert(title, errorText(error));
    } finally {
      actionLock.current = false;
      setBusy(false);
    }
  }

  async function loadMenus(showSpinner = true) {
    const requestId = ++menuRequest.current;
    if (showSpinner) setMenusLoading(true);
    try {
      const result = await listManagedMenusV2(sessionToken, deviceToken, {
        q: menuQuery,
        status: menuStatus,
        order: menuOrder
      });
      if (requestId !== menuRequest.current) return;
      setMenus(result.menus);
      if (selectedMenu) {
        const nextSelected = result.menus.find((menu) => menu.id === selectedMenu.id) || selectedMenu;
        setSelectedMenu(nextSelected);
      }
    } catch (error) {
      if (requestId === menuRequest.current) Alert.alert("Menus indisponíveis", errorText(error));
    } finally {
      if (requestId === menuRequest.current && showSpinner) setMenusLoading(false);
    }
  }

  async function loadKeys(menu = selectedMenu, showSpinner = true) {
    if (!menu) return;
    const requestId = ++keyRequest.current;
    if (showSpinner) setKeysLoading(true);
    try {
      const result = await listMenuKeysV2(sessionToken, deviceToken, menu.id, {
        q: keyQuery,
        kind: keyKind,
        order: keyOrder
      });
      if (requestId === keyRequest.current) setKeys(result.keys);
    } catch (error) {
      if (requestId === keyRequest.current) {
        setKeys([]);
        Alert.alert("Chaves indisponíveis", errorText(error));
      }
    } finally {
      if (requestId === keyRequest.current && showSpinner) setKeysLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => { loadMenus().catch(() => {}); }, 260);
    return () => clearTimeout(timer);
  }, [sessionToken, deviceToken, menuQuery, menuStatus, menuOrder]);

  useEffect(() => {
    if (!selectedMenu) return;
    const timer = setTimeout(() => { loadKeys(selectedMenu).catch(() => {}); }, 260);
    return () => clearTimeout(timer);
  }, [selectedMenu?.id, keyQuery, keyKind, keyOrder]);

  async function chooseMenu(menu: ManagedMenuV2) {
    setSelectedMenu(menu);
    setKeyQuery("");
    setKeyKind("ALL");
    setKeyOrder("RECENT");
    setKeys([]);
  }

  function newMenu() {
    if (busy) return;
    setMenuEditorTarget(null);
    setMenuName("");
    setSourceMode("INLINE");
    setSourceCode("");
    setSourceUrl("");
    setMenuEditorOpen(true);
  }

  async function editMenu(menu: ManagedMenuV2) {
    if (busy) return;
    setMenuEditorTarget(menu);
    setMenuName(menu.name);
    setSourceMode(menu.source_kind === "INLINE_ENCRYPTED" ? "INLINE" : "URL");
    setSourceCode("");
    setSourceUrl("");
    setMenuEditorOpen(true);
    setSourceLoading(true);
    try {
      const source = await getManagedMenuSourceV2(sessionToken, deviceToken, menu.id);
      if (source.sourceKind === "INLINE_ENCRYPTED") {
        setSourceMode("INLINE");
        setSourceCode(source.sourceCode || "");
      } else {
        setSourceMode("URL");
        setSourceUrl(source.sourceUrl || "");
      }
    } catch (error) {
      setMenuEditorOpen(false);
      Alert.alert("Fonte indisponível", errorText(error));
    } finally {
      setSourceLoading(false);
    }
  }

  async function importLuaFile() {
    if (busy || sourceLoading) return;
    let pickedUri: string | null = null;
    setBusy(true);
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
      if (!ALLOWED_LUA_EXTENSIONS.has(extension)) {
        throw new Error("Selecione um arquivo .lua ou .luau.");
      }

      const info = await FileSystem.getInfoAsync(asset.uri).catch(() => null);
      const knownSize = info && typeof info === "object" && "exists" in info && info.exists === true && "size" in info && typeof info.size === "number"
        ? info.size
        : typeof asset.size === "number"
          ? asset.size
          : 0;
      if (knownSize > MAX_PRIVATE_LUA_BYTES) {
        throw new Error("O arquivo ultrapassa o limite de 4 MB para código Lua privado.");
      }

      let content = await FileSystem.readAsStringAsync(asset.uri, { encoding: FileSystem.EncodingType.UTF8 });
      if (content.charCodeAt(0) === 0xfeff) content = content.slice(1);
      if (!content.trim()) {
        throw new Error("Este arquivo não contém código Lua.");
      }

      const bytes = new TextEncoder().encode(content).byteLength;
      if (bytes > MAX_PRIVATE_LUA_BYTES) {
        throw new Error("O conteúdo ultrapassa o limite de 4 MB para código Lua privado.");
      }

      setSourceMode("INLINE");
      setSourceCode(content);
      if (!menuName.trim()) {
        setMenuName(sourceName.replace(/\.(lua|luau)$/i, "").slice(0, 100));
      }
    } catch (error) {
      Alert.alert("Não foi possível importar", errorText(error));
    } finally {
      await cleanupPickerCopy(pickedUri);
      setBusy(false);
    }
  }

  async function saveMenu() {
    if (busy || sourceLoading) return;
    const name = menuName.trim();
    if (name.length < 2) {
      Alert.alert("Nome obrigatório", "Informe um nome para o menu.");
      return;
    }
    if (sourceMode === "INLINE" && !sourceCode.trim()) {
      Alert.alert("Código obrigatório", "Cole ou importe o código Lua do menu.");
      return;
    }
    if (sourceMode === "URL" && !sourceUrl.trim()) {
      Alert.alert("URL obrigatória", "Informe a URL HTTPS do arquivo .lua no GitHub.");
      return;
    }

    await runLocked(async () => {
      const sourceInput = sourceMode === "INLINE"
        ? { sourceCode }
        : { sourceUrl: sourceUrl.trim() };
      if (menuEditorTarget) {
        const result = await updateManagedMenuV2(sessionToken, deviceToken, menuEditorTarget.id, { name, ...sourceInput });
        if (selectedMenu?.id === menuEditorTarget.id) setSelectedMenu(result.menu);
      } else {
        await createManagedMenuV2(sessionToken, deviceToken, { name, ...sourceInput });
      }
      setMenuEditorOpen(false);
      await loadMenus(false);
    }, menuEditorTarget ? "Não foi possível salvar" : "Não foi possível criar o menu");
  }

  async function copyLoader(menu: ManagedMenuV2) {
    const loader = buildMenuLoader(menu.public_id);
    if (!loader) {
      Alert.alert("ID inválido", "Não foi possível gerar o loadstring deste menu.");
      return;
    }
    await Clipboard.setStringAsync(loader);
    Alert.alert("Loadstring copiado", `${menu.name} foi copiado para a área de transferência.`);
  }

  function requestSuspend(menu: ManagedMenuV2) {
    setSuspendTarget(menu);
    setSuspendMinutes("");
  }

  async function saveSuspension() {
    if (!suspendTarget) return;
    let duration: number | undefined;
    if (suspendMinutes.trim()) {
      const parsed = positiveInteger(suspendMinutes);
      if (!parsed || parsed > 43200) {
        Alert.alert("Duração inválida", "Use de 1 minuto a 43200 minutos (30 dias), ou deixe vazio para suspender sem prazo.");
        return;
      }
      duration = parsed;
    }
    await runLocked(async () => {
      const result = await setManagedMenuStateV2(sessionToken, deviceToken, suspendTarget.id, "suspend", duration);
      if (selectedMenu?.id === result.menu.id) setSelectedMenu(result.menu);
      setSuspendTarget(null);
      await loadMenus(false);
    }, "Não foi possível suspender");
  }

  function restoreMenu(menu: ManagedMenuV2) {
    Alert.alert("Ativar menu", `Liberar novamente ${menu.name}?`, [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Ativar",
        onPress: () => {
          runLocked(async () => {
            const result = await setManagedMenuStateV2(sessionToken, deviceToken, menu.id, "restore");
            if (selectedMenu?.id === result.menu.id) setSelectedMenu(result.menu);
            await loadMenus(false);
          }, "Não foi possível ativar").catch(() => {});
        }
      }
    ]);
  }

  function claimMenu(menu: ManagedMenuV2) {
    Alert.alert(
      "Assumir menu legado",
      "Este menu não possui proprietário registrado porque foi criado antes do sistema de contas. Ao assumir, ele ficará privado para esta conta DEV.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Assumir",
          onPress: () => {
            runLocked(async () => {
              const result = await claimLegacyMenuV2(sessionToken, deviceToken, menu.id);
              if (selectedMenu?.id === result.menu.id) setSelectedMenu(result.menu);
              await loadMenus(false);
            }, "Não foi possível assumir").catch(() => {});
          }
        }
      ]
    );
  }

  function removeMenu(menu: ManagedMenuV2) {
    Alert.alert(
      "Excluir menu",
      `Excluir ${menu.name}? Todas as chaves e sessões atuais serão invalidadas imediatamente. Esta ação remove o menu das listagens.`,
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Excluir",
          style: "destructive",
          onPress: () => {
            runLocked(async () => {
              await deleteManagedMenuV2(sessionToken, deviceToken, menu.id);
              if (selectedMenu?.id === menu.id) {
                setSelectedMenu(null);
                setKeys([]);
              }
              await loadMenus(false);
            }, "Não foi possível excluir").catch(() => {});
          }
        }
      ]
    );
  }

  function openNewKey() {
    if (!selectedMenu || selectedMenu.status !== "ACTIVE") return;
    setKeyName("");
    setNewKeyKind("FREE");
    setKeyDuration("24");
    setKeyVipUnit("DAYS");
    setKeyNote("");
    setKeyEditorOpen(true);
  }

  async function saveKey() {
    if (!selectedMenu) return;
    const name = keyName.trim();
    if (name.length < 2) {
      Alert.alert("Nome obrigatório", "Dê um nome para identificar a chave.");
      return;
    }
    const numeric = positiveInteger(keyDuration);
    if (!(newKeyKind === "VIP" && keyVipUnit === "PERMANENT") && numeric == null) {
      Alert.alert("Validade inválida", "Digite um número inteiro maior que zero.");
      return;
    }
    if (newKeyKind === "FREE" && (numeric || 0) > 24) {
      Alert.alert("Limite FREE", "FREE aceita de 1 a 24 horas.");
      return;
    }

    await runLocked(async () => {
      const result = await createMenuKeyV2(sessionToken, deviceToken, selectedMenu.id, {
        name,
        kind: newKeyKind,
        durationValue: newKeyKind === "VIP" && keyVipUnit === "PERMANENT" ? undefined : numeric || 1,
        durationUnit: newKeyKind === "VIP" ? keyVipUnit : undefined,
        note: keyNote.trim() || undefined
      });
      setKeyEditorOpen(false);
      setRevealed({ name: result.key.name, value: result.key.value });
      await Promise.all([loadKeys(selectedMenu, false), loadMenus(false)]);
    }, "Não foi possível gerar a chave");
  }

  async function revealKey(key: MenuKeyV2) {
    if (!key.can_reveal) {
      Alert.alert("Valor antigo indisponível", "Esta chave foi criada quando o servidor guardava somente o hash. Ela continua válida, mas o texto original não pode ser recuperado.");
      return;
    }
    await runLocked(async () => {
      const result = await revealMenuKeyV2(sessionToken, deviceToken, key.id);
      setRevealed({ name: result.key.name, value: result.key.value });
    }, "Não foi possível revelar");
  }

  function openRenew(key: MenuKeyV2) {
    setRenewTarget(key);
    if (key.kind === "FREE") {
      setRenewDuration(String(Math.min(24, Math.max(1, key.duration_value || 24))));
      setRenewVipUnit("DAYS");
    } else {
      const unit: VipUnit = key.duration_unit === "MONTHS" || key.duration_unit === "PERMANENT" ? key.duration_unit : "DAYS";
      setRenewVipUnit(unit);
      setRenewDuration(String(Math.max(1, key.duration_value || (unit === "MONTHS" ? 1 : 30))));
    }
  }

  async function saveRenew() {
    if (!renewTarget || !selectedMenu) return;
    if (renewTarget.kind === "FREE") {
      const hours = positiveInteger(renewDuration);
      if (!hours || hours > 24) {
        Alert.alert("Duração inválida", "Escolha entre 1 e 24 horas.");
        return;
      }
      await runLocked(async () => {
        await releaseFreeKeyV2(sessionToken, deviceToken, renewTarget.id, hours);
        setRenewTarget(null);
        await loadKeys(selectedMenu, false);
      }, "Não foi possível liberar a FREE");
      return;
    }

    const value = renewVipUnit === "PERMANENT" ? undefined : positiveInteger(renewDuration);
    if (renewVipUnit !== "PERMANENT" && !value) {
      Alert.alert("Validade inválida", "Digite um número inteiro maior que zero.");
      return;
    }
    await runLocked(async () => {
      await configureVipKeyV2(sessionToken, deviceToken, renewTarget.id, renewVipUnit, value || undefined);
      setRenewTarget(null);
      await loadKeys(selectedMenu, false);
    }, "Não foi possível configurar a VIP");
  }

  function resetKeyDevice(key: MenuKeyV2) {
    Alert.alert(
      "Trocar celular",
      "O aparelho atual será desvinculado e as sessões existentes serão encerradas. O tempo já iniciado da chave não será reiniciado.",
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Desvincular",
          style: "destructive",
          onPress: () => {
            runLocked(async () => {
              await resetMenuKeyDeviceV2(sessionToken, deviceToken, key.id);
              await loadKeys(selectedMenu, false);
            }, "Não foi possível trocar o aparelho").catch(() => {});
          }
        }
      ]
    );
  }

  function removeKey(key: MenuKeyV2) {
    Alert.alert(
      "Excluir chave",
      `Excluir ${key.name}? O acesso será invalidado imediatamente e a chave desaparecerá desta lista.`,
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Excluir",
          style: "destructive",
          onPress: () => {
            runLocked(async () => {
              await deleteMenuKeyV2(sessionToken, deviceToken, key.id);
              await Promise.all([loadKeys(selectedMenu, false), loadMenus(false)]);
            }, "Não foi possível excluir").catch(() => {});
          }
        }
      ]
    );
  }

  const usableKeys = useMemo(() => keys.filter((key) => key.usable).length, [keys]);

  if (!selectedMenu) {
    return (
      <View>
        <View style={s.heroCard}>
          <View style={{ flex: 1 }}>
            <Text style={s.heroTitle}>Menus e chaves</Text>
            <Text style={s.heroText}>Cadastre seu Lua, gere o loadstring e administre FREE/VIP no mesmo lugar.</Text>
          </View>
          <Pressable style={[s.primaryMini, busy && s.disabled]} disabled={busy} onPress={newMenu}>
            <Text style={s.primaryMiniText}>＋ MENU</Text>
          </Pressable>
        </View>

        <TextInput
          value={menuQuery}
          onChangeText={setMenuQuery}
          style={s.search}
          placeholder="Buscar menu..."
          placeholderTextColor="#626269"
          autoCorrect={false}
        />
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filterRow}>
          <Chip label="TODOS" active={!menuStatus} onPress={() => setMenuStatus("")} />
          <Chip label="ATIVOS" active={menuStatus === "ACTIVE"} onPress={() => setMenuStatus("ACTIVE")} />
          <Chip label="SUSPENSOS" active={menuStatus === "SUSPENDED"} onPress={() => setMenuStatus("SUSPENDED")} />
          <Chip label="RECENTES" active={menuOrder === "RECENT"} onPress={() => setMenuOrder("RECENT")} />
          <Chip label="ANTIGOS" active={menuOrder === "OLD"} onPress={() => setMenuOrder("OLD")} />
        </ScrollView>

        {menusLoading ? <ActivityIndicator style={{ marginTop: 28 }} /> : menus.length === 0 ? (
          <View style={s.emptyCard}>
            <Text style={s.emptyTitle}>Nenhum menu encontrado</Text>
            <Text style={s.emptyText}>Crie um menu colando/importando Lua ou usando uma URL .lua do GitHub.</Text>
          </View>
        ) : menus.map((menu) => (
          <View key={menu.id} style={[s.menuCard, menu.status === "SUSPENDED" && s.menuSuspended]}>
            <Pressable style={s.menuMain} disabled={busy} onPress={() => { chooseMenu(menu).catch(() => {}); }}>
              <View style={s.badgeRow}>
                <Text style={menu.status === "ACTIVE" ? s.ok : s.warn}>{menu.status === "ACTIVE" ? "ATIVO" : "SUSPENSO"}</Text>
                <Text style={s.sourceBadge}>{sourceLabel(menu)}</Text>
                {menu.legacy_unowned ? <Text style={s.legacyBadge}>LEGADO</Text> : null}
              </View>
              <Text style={s.cardTitle}>{menu.name}</Text>
              <Text style={s.meta}>{menu.public_id}</Text>
              <Text style={s.meta}>{menu.key_count} chave(s) • {menu.active_access_count} acesso(s) ativo(s)</Text>
              {menu.suspended_until ? <Text style={s.warnMeta}>Suspenso até {dateText(menu.suspended_until)}</Text> : null}
            </Pressable>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.actions}>
              <Action label="CHAVES" onPress={() => { chooseMenu(menu).catch(() => {}); }} disabled={busy} />
              <Action label="LOADSTRING" onPress={() => { copyLoader(menu).catch(() => {}); }} disabled={busy} />
              <Action label="EDITAR" onPress={() => { editMenu(menu).catch(() => {}); }} disabled={busy} />
              {menu.legacy_unowned ? <Action label="ASSUMIR" onPress={() => claimMenu(menu)} disabled={busy} /> : null}
              {menu.status === "ACTIVE"
                ? <Action label="SUSPENDER" onPress={() => requestSuspend(menu)} disabled={busy} />
                : <Action label="ATIVAR" onPress={() => restoreMenu(menu)} disabled={busy} />}
              <Action label="EXCLUIR" danger onPress={() => removeMenu(menu)} disabled={busy} />
            </ScrollView>
          </View>
        ))}

        <MenuEditorModal
          visible={menuEditorOpen}
          editing={Boolean(menuEditorTarget)}
          busy={busy}
          sourceLoading={sourceLoading}
          name={menuName}
          sourceMode={sourceMode}
          sourceCode={sourceCode}
          sourceUrl={sourceUrl}
          onName={setMenuName}
          onSourceMode={setSourceMode}
          onSourceCode={setSourceCode}
          onSourceUrl={setSourceUrl}
          onImport={() => { importLuaFile().catch(() => {}); }}
          onSave={() => { saveMenu().catch(() => {}); }}
          onClose={() => !busy && !sourceLoading && setMenuEditorOpen(false)}
        />

        <SuspensionModal
          target={suspendTarget}
          busy={busy}
          minutes={suspendMinutes}
          onMinutes={setSuspendMinutes}
          onSave={() => { saveSuspension().catch(() => {}); }}
          onClose={() => !busy && setSuspendTarget(null)}
        />
      </View>
    );
  }

  return (
    <View>
      <View style={s.detailHeader}>
        <Pressable style={s.backButton} disabled={busy} onPress={() => { setSelectedMenu(null); setKeys([]); }}>
          <Text style={s.backText}>‹ MENUS</Text>
        </Pressable>
        <View style={{ flex: 1 }}>
          <Text numberOfLines={1} style={s.detailTitle}>{selectedMenu.name}</Text>
          <Text style={s.meta}>{selectedMenu.public_id}</Text>
        </View>
        <Pressable style={s.iconButton} disabled={busy} onPress={() => { copyLoader(selectedMenu).catch(() => {}); }}>
          <Text style={s.iconButtonText}>LOAD</Text>
        </Pressable>
        <Pressable
          style={[s.primaryMini, (busy || selectedMenu.status !== "ACTIVE") && s.disabled]}
          disabled={busy || selectedMenu.status !== "ACTIVE"}
          onPress={openNewKey}
        >
          <Text style={s.primaryMiniText}>＋ CHAVE</Text>
        </Pressable>
      </View>

      {selectedMenu.status === "SUSPENDED" ? (
        <View style={s.suspendedNotice}>
          <Text style={s.suspendedTitle}>Menu suspenso</Text>
          <Text style={s.suspendedText}>Novas chaves ficam bloqueadas até o menu ser ativado. Chaves existentes continuam cadastradas, mas não liberam acesso.</Text>
          <Pressable style={s.noticeButton} onPress={() => restoreMenu(selectedMenu)} disabled={busy}>
            <Text style={s.noticeButtonText}>ATIVAR MENU</Text>
          </Pressable>
        </View>
      ) : null}

      <View style={s.statsRow}>
        <Stat label="VISÍVEIS" value={String(keys.length)} />
        <Stat label="UTILIZÁVEIS" value={String(usableKeys)} />
        <Stat label="FREE" value={String(keys.filter((key) => key.kind === "FREE").length)} />
        <Stat label="VIP" value={String(keys.filter((key) => key.kind === "VIP").length)} />
      </View>

      <TextInput
        value={keyQuery}
        onChangeText={setKeyQuery}
        style={s.search}
        placeholder="Buscar por nome, observação ou chave..."
        placeholderTextColor="#626269"
        autoCorrect={false}
      />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.filterRow}>
        <Chip label="TODAS" active={keyKind === "ALL"} onPress={() => setKeyKind("ALL")} />
        <Chip label="FREE" active={keyKind === "FREE"} onPress={() => setKeyKind("FREE")} />
        <Chip label="VIP" active={keyKind === "VIP"} onPress={() => setKeyKind("VIP")} />
        <Chip label="RECENTES" active={keyOrder === "RECENT"} onPress={() => setKeyOrder("RECENT")} />
        <Chip label="ANTIGAS" active={keyOrder === "OLD"} onPress={() => setKeyOrder("OLD")} />
      </ScrollView>

      {keysLoading ? <ActivityIndicator style={{ marginTop: 28 }} /> : keys.length === 0 ? (
        <View style={s.emptyCard}>
          <Text style={s.emptyTitle}>Nenhuma chave encontrada</Text>
          <Text style={s.emptyText}>Crie uma FREE/VIP ou altere os filtros.</Text>
        </View>
      ) : keys.map((key) => (
        <View key={key.id} style={s.keyCard}>
          <View style={s.badgeRow}>
            <Text style={[s.kindBadge, key.kind === "VIP" && s.vipBadge]}>{key.kind}</Text>
            <Text style={key.usable ? s.ok : s.warn}>{keyStateText(key)}</Text>
          </View>
          <Text style={s.cardTitle}>{key.name}</Text>
          <Text style={s.secretHint}>{key.key_hint}</Text>
          <Text style={s.meta}>{durationText(key)}{key.note ? ` • ${key.note}` : ""}</Text>
          <Text style={s.meta}>Aparelho: {key.bound_device ? key.bound_device_hint || "vinculado" : "não vinculado"}</Text>
          <Text style={s.meta}>Início: {dateText(key.access_started_at)} • Até: {key.duration_unit === "PERMANENT" && key.access_state === "ACTIVE" ? "PERMANENTE" : dateText(key.access_until)}</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.actions}>
            <Action label={key.can_reveal ? "VER CHAVE" : "VALOR ANTIGO"} onPress={() => { revealKey(key).catch(() => {}); }} disabled={busy} />
            {key.kind === "FREE" ? <Action label={key.access_state === "WAITING_ADMIN" ? "LIBERAR FREE" : "RECONFIGURAR"} onPress={() => openRenew(key)} disabled={busy} /> : null}
            {key.kind === "VIP" ? <Action label={key.access_state === "EXPIRED" ? "RENOVAR VIP" : "RECONFIGURAR"} onPress={() => openRenew(key)} disabled={busy} /> : null}
            {key.bound_device ? <Action label="TROCAR CELULAR" onPress={() => resetKeyDevice(key)} disabled={busy} /> : null}
            <Action label="EXCLUIR" danger onPress={() => removeKey(key)} disabled={busy} />
          </ScrollView>
        </View>
      ))}

      <KeyCreateModal
        visible={keyEditorOpen}
        busy={busy}
        name={keyName}
        kind={newKeyKind}
        duration={keyDuration}
        vipUnit={keyVipUnit}
        note={keyNote}
        onName={setKeyName}
        onKind={(kind) => { setNewKeyKind(kind); setKeyDuration(kind === "FREE" ? "24" : "30"); setKeyVipUnit("DAYS"); }}
        onDuration={setKeyDuration}
        onVipUnit={setKeyVipUnit}
        onNote={setKeyNote}
        onSave={() => { saveKey().catch(() => {}); }}
        onClose={() => !busy && setKeyEditorOpen(false)}
      />

      <RenewModal
        target={renewTarget}
        busy={busy}
        duration={renewDuration}
        vipUnit={renewVipUnit}
        onDuration={setRenewDuration}
        onVipUnit={setRenewVipUnit}
        onSave={() => { saveRenew().catch(() => {}); }}
        onClose={() => !busy && setRenewTarget(null)}
      />

      <SecretModal secret={revealed} onClose={() => setRevealed(null)} />
    </View>
  );
}

function MenuEditorModal(props: {
  visible: boolean;
  editing: boolean;
  busy: boolean;
  sourceLoading: boolean;
  name: string;
  sourceMode: SourceMode;
  sourceCode: string;
  sourceUrl: string;
  onName: (value: string) => void;
  onSourceMode: (value: SourceMode) => void;
  onSourceCode: (value: string) => void;
  onSourceUrl: (value: string) => void;
  onImport: () => void;
  onSave: () => void;
  onClose: () => void;
}) {
  return (
    <Modal visible={props.visible} transparent animationType="fade" onRequestClose={props.onClose}>
      <View style={s.modalBackdrop}>
        <View style={s.modalPanelLarge}>
          <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingBottom: 4 }}>
            <Text style={s.modalEyebrow}>{props.editing ? "EDITAR MENU" : "NOVO MENU"}</Text>
            <Text style={s.modalTitle}>{props.editing ? "Atualizar menu" : "Cadastrar menu"}</Text>
            {props.sourceLoading ? <ActivityIndicator style={{ marginVertical: 24 }} /> : (
              <>
                <Text style={s.label}>NOME</Text>
                <TextInput value={props.name} onChangeText={props.onName} editable={!props.busy} maxLength={100} style={s.input} placeholder="Ex.: CAFEÍNA Shooter" placeholderTextColor="#666" />
                <Text style={s.label}>FONTE DO MENU</Text>
                <View style={s.choiceRow}>
                  <Chip label="COLAR / IMPORTAR LUA" active={props.sourceMode === "INLINE"} onPress={() => props.onSourceMode("INLINE")} />
                  <Chip label="URL GITHUB" active={props.sourceMode === "URL"} onPress={() => props.onSourceMode("URL")} />
                </View>
                {props.sourceMode === "INLINE" ? (
                  <>
                    <Pressable style={s.importButton} disabled={props.busy} onPress={props.onImport}>
                      <Text style={s.importButtonText}>IMPORTAR .LUA / .LUAU</Text>
                    </Pressable>
                    <TextInput
                      value={props.sourceCode}
                      onChangeText={props.onSourceCode}
                      editable={!props.busy}
                      multiline
                      textAlignVertical="top"
                      style={[s.input, s.codeInput]}
                      placeholder="Cole o código Lua aqui..."
                      placeholderTextColor="#666"
                      autoCapitalize="none"
                      autoCorrect={false}
                    />
                    <Text style={s.help}>O código é criptografado no servidor. O loader recebe somente um link temporário depois de validar a chave.</Text>
                  </>
                ) : (
                  <>
                    <TextInput value={props.sourceUrl} onChangeText={props.onSourceUrl} editable={!props.busy} style={s.input} placeholder="https://github.com/.../arquivo.lua" placeholderTextColor="#666" autoCapitalize="none" autoCorrect={false} />
                    <Text style={s.help}>Aceita HTTPS do GitHub ou raw.githubusercontent.com apontando para .lua.</Text>
                  </>
                )}
                <Pressable style={[s.saveButton, props.busy && s.disabled]} disabled={props.busy} onPress={props.onSave}>
                  <Text style={s.saveButtonText}>{props.busy ? "SALVANDO..." : props.editing ? "SALVAR ALTERAÇÕES" : "CRIAR MENU"}</Text>
                </Pressable>
                <Pressable style={s.cancelButton} disabled={props.busy} onPress={props.onClose}><Text style={s.cancelText}>CANCELAR</Text></Pressable>
              </>
            )}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

function SuspensionModal(props: {
  target: ManagedMenuV2 | null;
  busy: boolean;
  minutes: string;
  onMinutes: (value: string) => void;
  onSave: () => void;
  onClose: () => void;
}) {
  return (
    <Modal visible={Boolean(props.target)} transparent animationType="fade" onRequestClose={props.onClose}>
      <View style={s.modalBackdrop}>
        <View style={s.modalPanel}>
          <Text style={s.modalEyebrow}>SUSPENDER MENU</Text>
          <Text style={s.modalTitle}>{props.target?.name}</Text>
          <Text style={s.help}>Enquanto suspenso, nenhuma chave libera o menu e as sessões atuais são encerradas.</Text>
          <Text style={s.label}>TEMPO EM MINUTOS • VAZIO = SEM PRAZO</Text>
          <TextInput value={props.minutes} onChangeText={props.onMinutes} editable={!props.busy} keyboardType="number-pad" style={s.input} placeholder="Sem prazo" placeholderTextColor="#666" />
          <View style={s.choiceRow}>
            <Chip label="1H" active={props.minutes === "60"} onPress={() => props.onMinutes("60")} />
            <Chip label="6H" active={props.minutes === "360"} onPress={() => props.onMinutes("360")} />
            <Chip label="24H" active={props.minutes === "1440"} onPress={() => props.onMinutes("1440")} />
            <Chip label="SEM PRAZO" active={props.minutes === ""} onPress={() => props.onMinutes("")} />
          </View>
          <Pressable style={[s.dangerButton, props.busy && s.disabled]} disabled={props.busy} onPress={props.onSave}>
            <Text style={s.dangerButtonText}>{props.busy ? "SALVANDO..." : "SUSPENDER"}</Text>
          </Pressable>
          <Pressable style={s.cancelButton} disabled={props.busy} onPress={props.onClose}><Text style={s.cancelText}>CANCELAR</Text></Pressable>
        </View>
      </View>
    </Modal>
  );
}

function KeyCreateModal(props: {
  visible: boolean;
  busy: boolean;
  name: string;
  kind: MenuKeyKindV2;
  duration: string;
  vipUnit: VipUnit;
  note: string;
  onName: (value: string) => void;
  onKind: (value: MenuKeyKindV2) => void;
  onDuration: (value: string) => void;
  onVipUnit: (value: VipUnit) => void;
  onNote: (value: string) => void;
  onSave: () => void;
  onClose: () => void;
}) {
  return (
    <Modal visible={props.visible} transparent animationType="fade" onRequestClose={props.onClose}>
      <View style={s.modalBackdrop}>
        <View style={s.modalPanel}>
          <ScrollView keyboardShouldPersistTaps="handled">
            <Text style={s.modalEyebrow}>NOVA CHAVE</Text>
            <Text style={s.modalTitle}>Gerar FREE / VIP</Text>
            <Text style={s.label}>NOME DA CHAVE</Text>
            <TextInput value={props.name} onChangeText={props.onName} editable={!props.busy} maxLength={80} style={s.input} placeholder="Ex.: Cliente João" placeholderTextColor="#666" />
            <View style={[s.choiceRow, { marginTop: 12 }]}>
              <Chip label="FREE" active={props.kind === "FREE"} onPress={() => props.onKind("FREE")} />
              <Chip label="VIP" active={props.kind === "VIP"} onPress={() => props.onKind("VIP")} />
            </View>
            {props.kind === "FREE" ? (
              <>
                <Text style={s.label}>HORAS • 1 A 24</Text>
                <TextInput value={props.duration} onChangeText={props.onDuration} editable={!props.busy} keyboardType="number-pad" style={s.input} placeholder="24" placeholderTextColor="#666" />
              </>
            ) : (
              <>
                <Text style={s.label}>VALIDADE VIP</Text>
                <View style={s.choiceRow}>
                  <Chip label="DIAS" active={props.vipUnit === "DAYS"} onPress={() => props.onVipUnit("DAYS")} />
                  <Chip label="MESES" active={props.vipUnit === "MONTHS"} onPress={() => props.onVipUnit("MONTHS")} />
                  <Chip label="PERMANENTE" active={props.vipUnit === "PERMANENT"} onPress={() => props.onVipUnit("PERMANENT")} />
                </View>
                {props.vipUnit !== "PERMANENT" ? <TextInput value={props.duration} onChangeText={props.onDuration} editable={!props.busy} keyboardType="number-pad" style={s.input} placeholder="30" placeholderTextColor="#666" /> : null}
              </>
            )}
            <TextInput value={props.note} onChangeText={props.onNote} editable={!props.busy} maxLength={200} style={s.input} placeholder="Observação opcional" placeholderTextColor="#666" />
            <Pressable style={[s.saveButton, props.busy && s.disabled]} disabled={props.busy} onPress={props.onSave}>
              <Text style={s.saveButtonText}>{props.busy ? "GERANDO..." : "GERAR CHAVE"}</Text>
            </Pressable>
            <Pressable style={s.cancelButton} disabled={props.busy} onPress={props.onClose}><Text style={s.cancelText}>CANCELAR</Text></Pressable>
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

function RenewModal(props: {
  target: MenuKeyV2 | null;
  busy: boolean;
  duration: string;
  vipUnit: VipUnit;
  onDuration: (value: string) => void;
  onVipUnit: (value: VipUnit) => void;
  onSave: () => void;
  onClose: () => void;
}) {
  return (
    <Modal visible={Boolean(props.target)} transparent animationType="fade" onRequestClose={props.onClose}>
      <View style={s.modalBackdrop}>
        <View style={s.modalPanel}>
          <Text style={s.modalEyebrow}>{props.target?.kind === "FREE" ? "FREE" : "VIP"}</Text>
          <Text style={s.modalTitle}>Reconfigurar {props.target?.name}</Text>
          {props.target?.kind === "FREE" ? (
            <>
              <Text style={s.help}>O próximo ciclo começa no próximo uso e pode ter de 1 a 24 horas.</Text>
              <TextInput value={props.duration} onChangeText={props.onDuration} editable={!props.busy} keyboardType="number-pad" style={s.input} placeholder="24" placeholderTextColor="#666" />
            </>
          ) : (
            <>
              <Text style={s.help}>Ao salvar, sessões atuais são encerradas e a nova validade começa no próximo uso.</Text>
              <View style={s.choiceRow}>
                <Chip label="DIAS" active={props.vipUnit === "DAYS"} onPress={() => props.onVipUnit("DAYS")} />
                <Chip label="MESES" active={props.vipUnit === "MONTHS"} onPress={() => props.onVipUnit("MONTHS")} />
                <Chip label="PERMANENTE" active={props.vipUnit === "PERMANENT"} onPress={() => props.onVipUnit("PERMANENT")} />
              </View>
              {props.vipUnit !== "PERMANENT" ? <TextInput value={props.duration} onChangeText={props.onDuration} editable={!props.busy} keyboardType="number-pad" style={s.input} placeholder="30" placeholderTextColor="#666" /> : null}
            </>
          )}
          <Pressable style={[s.saveButton, props.busy && s.disabled]} disabled={props.busy} onPress={props.onSave}>
            <Text style={s.saveButtonText}>{props.busy ? "SALVANDO..." : "SALVAR"}</Text>
          </Pressable>
          <Pressable style={s.cancelButton} disabled={props.busy} onPress={props.onClose}><Text style={s.cancelText}>CANCELAR</Text></Pressable>
        </View>
      </View>
    </Modal>
  );
}

function SecretModal({ secret, onClose }: { secret: RevealedSecret | null; onClose: () => void }) {
  return (
    <Modal visible={Boolean(secret)} transparent animationType="fade" onRequestClose={onClose}>
      <View style={s.modalBackdrop}>
        <View style={s.modalPanel}>
          <Text style={s.modalEyebrow}>VALOR DA CHAVE</Text>
          <Text style={s.modalTitle}>{secret?.name}</Text>
          <Text style={s.help}>O valor fica apenas neste modal enquanto aberto. Copiar envia para a área de transferência por sua ação explícita.</Text>
          <Text selectable style={s.secretValue}>{secret?.value}</Text>
          <Pressable style={s.saveButton} onPress={() => { if (secret?.value) Clipboard.setStringAsync(secret.value).catch(() => {}); }}>
            <Text style={s.saveButtonText}>COPIAR CHAVE</Text>
          </Pressable>
          <Pressable style={s.cancelButton} onPress={onClose}><Text style={s.cancelText}>FECHAR</Text></Pressable>
        </View>
      </View>
    </Modal>
  );
}

function Chip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable style={[s.chip, active && s.chipActive]} onPress={onPress}>
      <Text style={[s.chipText, active && s.chipTextActive]}>{label}</Text>
    </Pressable>
  );
}

function Action({ label, onPress, danger = false, disabled = false }: {
  label: string;
  onPress: () => void;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <Pressable style={[s.action, danger && s.actionDanger, disabled && s.disabled]} disabled={disabled} onPress={onPress}>
      <Text style={[s.actionText, danger && s.actionDangerText]}>{label}</Text>
    </Pressable>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={s.stat}>
      <Text style={s.statValue}>{value}</Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  heroCard: { flexDirection: "row", alignItems: "center", gap: 10, borderRadius: 16, borderWidth: 1, borderColor: "#302633", backgroundColor: "#0C090E", padding: 14, marginBottom: 10 },
  heroTitle: { color: "#FFF", fontSize: 16, fontWeight: "900" },
  heroText: { color: "#85818A", fontSize: 9, lineHeight: 14, marginTop: 4 },
  primaryMini: { minHeight: 38, borderRadius: 10, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 11 },
  primaryMiniText: { color: "#050505", fontSize: 8, fontWeight: "900" },
  search: { minHeight: 46, borderRadius: 12, borderWidth: 1, borderColor: "#292930", backgroundColor: "#0D0D10", color: "#FFF", paddingHorizontal: 12, marginTop: 4 },
  filterRow: { flexDirection: "row", gap: 6, paddingVertical: 9, paddingRight: 8 },
  chip: { minHeight: 34, borderRadius: 9, borderWidth: 1, borderColor: "#313138", backgroundColor: "#0B0B0E", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  chipActive: { backgroundColor: "#FFF", borderColor: "#FFF" },
  chipText: { color: "#85858D", fontSize: 7, fontWeight: "900" },
  chipTextActive: { color: "#050505" },
  menuCard: { borderRadius: 15, borderWidth: 1, borderColor: "#27272D", backgroundColor: "#09090B", marginBottom: 9, overflow: "hidden" },
  menuSuspended: { borderColor: "#4A292D", backgroundColor: "#0E090A" },
  menuMain: { padding: 13 },
  badgeRow: { flexDirection: "row", alignItems: "center", flexWrap: "wrap", gap: 6, marginBottom: 6 },
  ok: { color: "#6DDB86", fontSize: 8, fontWeight: "900" },
  warn: { color: "#FF767D", fontSize: 8, fontWeight: "900" },
  sourceBadge: { color: "#C4A6D8", backgroundColor: "#160F1B", borderRadius: 5, paddingHorizontal: 5, paddingVertical: 2, fontSize: 7, fontWeight: "900" },
  legacyBadge: { color: "#F2C36B", backgroundColor: "#1B1407", borderRadius: 5, paddingHorizontal: 5, paddingVertical: 2, fontSize: 7, fontWeight: "900" },
  kindBadge: { color: "#6DDB86", fontSize: 8, fontWeight: "900" },
  vipBadge: { color: "#D7A1FA" },
  cardTitle: { color: "#FFF", fontSize: 13, fontWeight: "900" },
  meta: { color: "#707078", fontSize: 8, lineHeight: 13, marginTop: 3 },
  warnMeta: { color: "#D8898D", fontSize: 8, marginTop: 4 },
  secretHint: { color: "#A8A8AF", fontSize: 9, fontWeight: "700", marginTop: 4 },
  actions: { flexDirection: "row", gap: 6, paddingHorizontal: 11, paddingBottom: 11 },
  action: { minHeight: 32, borderRadius: 8, borderWidth: 1, borderColor: "#34343A", alignItems: "center", justifyContent: "center", paddingHorizontal: 9 },
  actionDanger: { borderColor: "#51272B", backgroundColor: "#130809" },
  actionText: { color: "#BDBDC4", fontSize: 7, fontWeight: "900" },
  actionDangerText: { color: "#FF777D" },
  disabled: { opacity: 0.42 },
  emptyCard: { minHeight: 112, borderRadius: 15, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#09090B", alignItems: "center", justifyContent: "center", padding: 18, marginTop: 8 },
  emptyTitle: { color: "#FFF", fontSize: 12, fontWeight: "900" },
  emptyText: { color: "#6D6D75", fontSize: 9, lineHeight: 14, textAlign: "center", marginTop: 5 },
  detailHeader: { flexDirection: "row", alignItems: "center", gap: 7, marginBottom: 9 },
  backButton: { minHeight: 38, justifyContent: "center", paddingRight: 4 },
  backText: { color: "#B7B7BE", fontSize: 8, fontWeight: "900" },
  detailTitle: { color: "#FFF", fontSize: 14, fontWeight: "900" },
  iconButton: { minHeight: 38, borderRadius: 9, borderWidth: 1, borderColor: "#403247", alignItems: "center", justifyContent: "center", paddingHorizontal: 8 },
  iconButtonText: { color: "#C6A7D8", fontSize: 7, fontWeight: "900" },
  suspendedNotice: { borderRadius: 13, borderWidth: 1, borderColor: "#542A2F", backgroundColor: "#120809", padding: 12, marginBottom: 9 },
  suspendedTitle: { color: "#FF7B81", fontSize: 11, fontWeight: "900" },
  suspendedText: { color: "#9D777A", fontSize: 8, lineHeight: 13, marginTop: 4 },
  noticeButton: { minHeight: 35, borderRadius: 9, borderWidth: 1, borderColor: "#633239", alignItems: "center", justifyContent: "center", marginTop: 8 },
  noticeButtonText: { color: "#FF8D92", fontSize: 7, fontWeight: "900" },
  statsRow: { flexDirection: "row", gap: 6, marginBottom: 5 },
  stat: { flex: 1, borderRadius: 10, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#09090B", alignItems: "center", paddingVertical: 8 },
  statValue: { color: "#FFF", fontSize: 12, fontWeight: "900" },
  statLabel: { color: "#66666E", fontSize: 6, fontWeight: "900", marginTop: 2 },
  keyCard: { borderRadius: 14, borderWidth: 1, borderColor: "#27272D", backgroundColor: "#09090B", padding: 12, marginBottom: 8 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.86)", alignItems: "center", justifyContent: "center", padding: 15 },
  modalPanel: { width: "100%", maxWidth: 520, maxHeight: "84%", borderRadius: 18, borderWidth: 1, borderColor: "#303037", backgroundColor: "#09090C", padding: 15 },
  modalPanelLarge: { width: "100%", maxWidth: 560, maxHeight: "90%", borderRadius: 18, borderWidth: 1, borderColor: "#303037", backgroundColor: "#09090C", padding: 15 },
  modalEyebrow: { color: "#A980BF", fontSize: 8, fontWeight: "900", letterSpacing: 1 },
  modalTitle: { color: "#FFF", fontSize: 19, fontWeight: "900", marginTop: 4, marginBottom: 8 },
  label: { color: "#77777F", fontSize: 8, fontWeight: "900", letterSpacing: 0.9, marginTop: 9, marginBottom: 2 },
  input: { minHeight: 47, borderRadius: 11, borderWidth: 1, borderColor: "#303037", backgroundColor: "#111114", color: "#FFF", paddingHorizontal: 11, marginTop: 6 },
  codeInput: { minHeight: 190, paddingTop: 10, paddingBottom: 10, fontSize: 11 },
  help: { color: "#787880", fontSize: 8, lineHeight: 13, marginTop: 7 },
  choiceRow: { flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 6 },
  importButton: { minHeight: 40, borderRadius: 10, borderWidth: 1, borderColor: "#493556", backgroundColor: "#140E18", alignItems: "center", justifyContent: "center", marginTop: 8 },
  importButtonText: { color: "#D1B2E2", fontSize: 8, fontWeight: "900" },
  saveButton: { minHeight: 47, borderRadius: 11, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 13 },
  saveButtonText: { color: "#050505", fontSize: 9, fontWeight: "900" },
  dangerButton: { minHeight: 47, borderRadius: 11, backgroundColor: "#5A2026", alignItems: "center", justifyContent: "center", marginTop: 13 },
  dangerButtonText: { color: "#FFF", fontSize: 9, fontWeight: "900" },
  cancelButton: { minHeight: 40, alignItems: "center", justifyContent: "center", marginTop: 3 },
  cancelText: { color: "#85858D", fontSize: 8, fontWeight: "900" },
  secretValue: { color: "#FFF", backgroundColor: "#111116", borderRadius: 11, borderWidth: 1, borderColor: "#34343A", padding: 12, fontSize: 11, lineHeight: 17, marginTop: 9 }
});
