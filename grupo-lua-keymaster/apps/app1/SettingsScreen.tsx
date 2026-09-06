import { useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import type { App1Role } from "./api";
import {
  authenticateForQuickUnlock,
  isQuickUnlockEnabled,
  setQuickUnlockEnabled
} from "./quickUnlock";
import {
  type PresenceMode,
  type PublicProfileView,
  getOwnProfile,
  updateOwnProfile
} from "./social-api";

const AVATARS = ["MOON", "CAT", "CODE", "GHOST"] as const;
const FRAMES = ["DEFAULT", "RED", "PURPLE", "SILVER"] as const;

function labelForAvatar(value: string) {
  if (value === "CAT") return "GATO";
  if (value === "CODE") return "CÓDIGO";
  if (value === "GHOST") return "GHOST";
  return "LUA";
}

function avatarGlyph(value: string) {
  if (value === "CAT") return "ฅ";
  if (value === "CODE") return "</>";
  if (value === "GHOST") return "◌";
  return "☾";
}

function labelForFrame(value: string) {
  if (value === "RED") return "VERMELHA";
  if (value === "PURPLE") return "ROXA";
  if (value === "SILVER") return "PRATA";
  return "PADRÃO";
}

export function SettingsScreen({
  sessionToken,
  deviceToken,
  role,
  onSignOut
}: {
  sessionToken: string;
  deviceToken: string;
  role: App1Role;
  onSignOut: () => void;
}) {
  const [profile, setProfile] = useState<PublicProfileView | null>(null);
  const [bio, setBio] = useState("");
  const [statusText, setStatusText] = useState("");
  const [avatarStyle, setAvatarStyle] = useState("MOON");
  const [frameStyle, setFrameStyle] = useState("DEFAULT");
  const [presenceMode, setPresenceMode] = useState<PresenceMode>("VISIBLE");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [quickUnlockEnabled, setQuickUnlockState] = useState(false);
  const [quickUnlockBusy, setQuickUnlockBusy] = useState(false);
  const mounted = useRef(true);

  function applyProfile(next: PublicProfileView) {
    setProfile(next);
    setBio(next.bio || "");
    setStatusText(next.statusText || "");
    setAvatarStyle(next.avatarStyle || "MOON");
    setFrameStyle(next.frameStyle || "DEFAULT");
    setPresenceMode(next.presenceMode || "VISIBLE");
  }

  async function load() {
    setLoading(true);
    setLoadError(null);
    try {
      const [result, localUnlock] = await Promise.all([
        getOwnProfile(sessionToken, deviceToken),
        isQuickUnlockEnabled().catch(() => false)
      ]);
      if (mounted.current) {
        applyProfile(result.profile);
        setQuickUnlockState(localUnlock);
      }
    } catch (error) {
      if (mounted.current) {
        setProfile(null);
        setQuickUnlockState(await isQuickUnlockEnabled().catch(() => false));
        setLoadError(error instanceof Error ? error.message : "Não foi possível carregar o perfil.");
      }
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

  const dirty = useMemo(() => {
    if (!profile) return false;
    return (
      bio.trim() !== (profile.bio || "") ||
      statusText.trim() !== (profile.statusText || "") ||
      avatarStyle !== (profile.avatarStyle || "MOON") ||
      frameStyle !== (profile.frameStyle || "DEFAULT") ||
      presenceMode !== (profile.presenceMode || "VISIBLE")
    );
  }, [profile, bio, statusText, avatarStyle, frameStyle, presenceMode]);

  function discardChanges() {
    if (!profile || saving) return;
    applyProfile(profile);
  }

  async function save() {
    if (saving || !profile || !dirty) return;
    setSaving(true);
    try {
      const result = await updateOwnProfile(sessionToken, deviceToken, {
        bio: bio.trim(),
        statusText: statusText.trim(),
        avatarStyle,
        frameStyle,
        presenceMode
      });
      if (mounted.current) {
        applyProfile(result.profile);
        Alert.alert("Perfil atualizado", "Suas configurações públicas foram salvas no servidor.");
      }
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Falha ao salvar", error instanceof Error ? error.message : "Não foi possível atualizar o perfil.");
      }
    } finally {
      if (mounted.current) setSaving(false);
    }
  }

  async function toggleQuickUnlock() {
    if (quickUnlockBusy) return;
    setQuickUnlockBusy(true);
    try {
      if (quickUnlockEnabled) {
        await setQuickUnlockEnabled(false);
        if (mounted.current) setQuickUnlockState(false);
        Alert.alert("Acesso rápido desativado", "Na próxima abertura, o app não exigirá a autenticação local antes de validar a sessão salva.");
        return;
      }

      const authentication = await authenticateForQuickUnlock();
      if (!authentication.ok) {
        Alert.alert("Não foi possível ativar", authentication.message);
        return;
      }
      await setQuickUnlockEnabled(true);
      if (mounted.current) setQuickUnlockState(true);
      Alert.alert(
        "Acesso rápido ativado",
        "Enquanto houver uma sessão válida salva neste aparelho, o GRUPO LUA pedirá a autenticação do celular antes de abrir a conta. A senha/chave da conta não é armazenada para isso."
      );
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível alterar o acesso rápido.");
    } finally {
      if (mounted.current) setQuickUnlockBusy(false);
    }
  }

  function confirmSignOut() {
    Alert.alert(
      "Sair da conta?",
      "A sessão deste aparelho será encerrada no servidor. A autorização do dispositivo será preservada.",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Sair", style: "destructive", onPress: onSignOut }
      ]
    );
  }

  useEffect(() => {
    mounted.current = true;
    load().catch(() => {});
    return () => { mounted.current = false; };
  }, [sessionToken, deviceToken]);

  if (loading) return <ActivityIndicator style={{ marginVertical: 32 }} />;

  if (!profile) {
    return (
      <View style={s.root}>
        <Text style={s.title}>Perfil e configurações</Text>
        <Text style={s.muted}>Não foi possível carregar seus dados públicos.</Text>
        <View style={s.errorCard}>
          <Text style={s.errorTitle}>Configurações de perfil indisponíveis</Text>
          <Text style={s.errorText}>{loadError || "Tente novamente em alguns instantes."}</Text>
          <Pressable style={s.retry} onPress={() => { load().catch(() => {}); }}>
            <Text style={s.retryText}>TENTAR NOVAMENTE</Text>
          </Pressable>
        </View>
        <SecurityActions
          quickUnlockEnabled={quickUnlockEnabled}
          quickUnlockBusy={quickUnlockBusy}
          onToggleQuickUnlock={toggleQuickUnlock}
          onSignOut={confirmSignOut}
        />
      </View>
    );
  }

  return (
    <View style={s.root}>
      <Text style={s.title}>Perfil e configurações</Text>
      <Text style={s.muted}>Personalização pública, privacidade e segurança deste aparelho.</Text>

      <View style={[s.profileCard, role === "DEV" && s.profileDev]}>
        <View style={[s.avatar, frameStyle === "RED" && s.frameRed, frameStyle === "PURPLE" && s.framePurple, frameStyle === "SILVER" && s.frameSilver]}>
          <Text style={[s.avatarText, avatarStyle === "CODE" && s.avatarCode]}>{avatarGlyph(avatarStyle)}</Text>
        </View>
        <View style={{ flex: 1 }}>
          <View style={s.identityRow}>
            <Text style={s.publicName}>{profile.publicName || "Perfil"}</Text>
            {role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
          </View>
          <Text style={s.muted}>Pseudônimo confirmado pelo servidor • {role}</Text>
          <Text style={s.previewMeta}>{labelForAvatar(avatarStyle)} • moldura {labelForFrame(frameStyle).toLowerCase()} • {presenceMode === "VISIBLE" ? "presença visível" : "presença oculta"}</Text>
        </View>
      </View>

      <Text style={s.label}>PENSAMENTO / STATUS</Text>
      <TextInput
        value={statusText}
        onChangeText={setStatusText}
        maxLength={80}
        editable={!saving}
        style={s.input}
        placeholder="Ex.: trabalhando em um menu novo..."
        placeholderTextColor="#626269"
      />
      <Text style={s.counter}>{Array.from(statusText).length}/80</Text>

      <Text style={s.label}>BIO</Text>
      <TextInput
        value={bio}
        onChangeText={setBio}
        maxLength={280}
        multiline
        editable={!saving}
        style={[s.input, s.bio]}
        placeholder="Uma descrição curta do seu perfil..."
        placeholderTextColor="#626269"
        textAlignVertical="top"
      />
      <Text style={s.counter}>{Array.from(bio).length}/280</Text>

      <Text style={s.label}>AVATAR</Text>
      <View style={s.choices}>
        {AVATARS.map((item) => (
          <Pressable key={item} disabled={saving} style={[s.choice, avatarStyle === item && s.choiceActive, saving && s.disabled]} onPress={() => setAvatarStyle(item)}>
            <Text style={[s.choiceText, avatarStyle === item && s.choiceTextActive]}>{labelForAvatar(item)}</Text>
          </Pressable>
        ))}
      </View>

      <Text style={s.label}>MOLDURA</Text>
      <View style={s.choices}>
        {FRAMES.map((item) => (
          <Pressable key={item} disabled={saving} style={[s.choice, frameStyle === item && s.choiceActive, saving && s.disabled]} onPress={() => setFrameStyle(item)}>
            <Text style={[s.choiceText, frameStyle === item && s.choiceTextActive]}>{labelForFrame(item)}</Text>
          </Pressable>
        ))}
      </View>

      <Text style={s.label}>PRESENÇA</Text>
      <View style={s.choices}>
        <Pressable disabled={saving} style={[s.choice, presenceMode === "VISIBLE" && s.choiceActive, saving && s.disabled]} onPress={() => setPresenceMode("VISIBLE")}>
          <Text style={[s.choiceText, presenceMode === "VISIBLE" && s.choiceTextActive]}>VISÍVEL</Text>
        </Pressable>
        <Pressable disabled={saving} style={[s.choice, presenceMode === "HIDDEN" && s.choiceActive, saving && s.disabled]} onPress={() => setPresenceMode("HIDDEN")}>
          <Text style={[s.choiceText, presenceMode === "HIDDEN" && s.choiceTextActive]}>OCULTA</Text>
        </Pressable>
      </View>
      <Text style={s.presenceHelp}>{presenceMode === "VISIBLE" ? "Seu status de presença pode aparecer para outros perfis." : "Seu perfil continua existindo, mas a presença não é exibida como visível."}</Text>

      <Pressable style={[s.save, (saving || !dirty) && s.disabled]} disabled={saving || !dirty} onPress={save}>
        <Text style={s.saveText}>{saving ? "SALVANDO..." : dirty ? "SALVAR CONFIGURAÇÕES" : "CONFIGURAÇÕES SALVAS"}</Text>
      </Pressable>
      {dirty ? (
        <Pressable style={[s.discard, saving && s.disabled]} disabled={saving} onPress={discardChanges}>
          <Text style={s.discardText}>DESFAZER ALTERAÇÕES</Text>
        </Pressable>
      ) : null}

      <SecurityActions
        quickUnlockEnabled={quickUnlockEnabled}
        quickUnlockBusy={quickUnlockBusy}
        onToggleQuickUnlock={toggleQuickUnlock}
        onSignOut={confirmSignOut}
      />
    </View>
  );
}

function SecurityActions({
  quickUnlockEnabled,
  quickUnlockBusy,
  onToggleQuickUnlock,
  onSignOut
}: {
  quickUnlockEnabled: boolean;
  quickUnlockBusy: boolean;
  onToggleQuickUnlock: () => void;
  onSignOut: () => void;
}) {
  return (
    <>
      <View style={s.securityCard}>
        <View style={s.securityRow}>
          <View style={{ flex: 1 }}>
            <Text style={s.securityTitle}>Acesso rápido neste celular</Text>
            <Text style={s.securityState}>{quickUnlockEnabled ? "ATIVADO" : "DESATIVADO"}</Text>
          </View>
          <Pressable
            style={[s.quickButton, quickUnlockEnabled && s.quickButtonActive, quickUnlockBusy && s.disabled]}
            disabled={quickUnlockBusy}
            onPress={onToggleQuickUnlock}
          >
            <Text style={[s.quickButtonText, quickUnlockEnabled && s.quickButtonTextActive]}>
              {quickUnlockBusy ? "AGUARDE" : quickUnlockEnabled ? "DESATIVAR" : "ATIVAR"}
            </Text>
          </Pressable>
        </View>
        <Text style={s.securityText}>
          Quando ativado, uma sessão já cadastrada só abre depois da autenticação local oferecida pelo sistema do celular. O app continua validando a sessão no servidor e não salva sua senha/chave de login para esse acesso.
        </Text>
      </View>

      <View style={s.securityCard}>
        <Text style={s.securityTitle}>Privacidade e segurança</Text>
        <Text style={s.securityText}>
          Login privado, chave, dispositivos autorizados, role real e bloqueios de segurança não podem ser alterados pelo perfil. Chats privados não possuem leitura administrativa comum enquanto a conta estiver ativa.
        </Text>
      </View>

      <Pressable style={s.signOut} onPress={onSignOut}>
        <Text style={s.signOutText}>SAIR DA CONTA</Text>
      </Pressable>
    </>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  title: { color: "#FFF", fontSize: 22, fontWeight: "900" },
  muted: { color: "#8A8A91", fontSize: 10, lineHeight: 15, marginTop: 3 },
  profileCard: { flexDirection: "row", alignItems: "center", gap: 12, borderRadius: 16, borderWidth: 1, borderColor: "#292930", backgroundColor: "#09090CC7", padding: 14, marginTop: 12, marginBottom: 12 },
  profileDev: { borderColor: "#4B2024" },
  avatar: { width: 48, height: 48, borderRadius: 24, borderWidth: 2, borderColor: "#45454D", backgroundColor: "#16161AD9", alignItems: "center", justifyContent: "center" },
  frameRed: { borderColor: "#E24A52" },
  framePurple: { borderColor: "#B47AE8" },
  frameSilver: { borderColor: "#D0D0D5" },
  avatarText: { color: "#FFF", fontSize: 20, fontWeight: "900" },
  avatarCode: { fontSize: 10 },
  identityRow: { flexDirection: "row", alignItems: "center", gap: 7 },
  publicName: { flexShrink: 1, color: "#FFF", fontSize: 15, fontWeight: "900" },
  devBadge: { color: "#FF686F", fontSize: 8, fontWeight: "900", backgroundColor: "#210A0CD9", borderRadius: 6, paddingHorizontal: 6, paddingVertical: 3 },
  previewMeta: { color: "#76767E", fontSize: 8, lineHeight: 13, marginTop: 5 },
  label: { color: "#8A8A92", fontSize: 9, fontWeight: "900", letterSpacing: 1.1, marginTop: 11 },
  input: { minHeight: 49, borderRadius: 12, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#101013C7", color: "#FFF", paddingHorizontal: 13, marginTop: 7 },
  bio: { minHeight: 105, paddingTop: 12, paddingBottom: 12 },
  counter: { color: "#707078", fontSize: 8, textAlign: "right", marginTop: 4 },
  choices: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 7 },
  choice: { borderWidth: 1, borderColor: "#3A3A40", backgroundColor: "#09090C9E", borderRadius: 10, paddingHorizontal: 11, paddingVertical: 9 },
  choiceActive: { backgroundColor: "#FFF", borderColor: "#FFF" },
  choiceText: { color: "#9B9BA3", fontSize: 8, fontWeight: "900" },
  choiceTextActive: { color: "#070708" },
  presenceHelp: { color: "#76767E", fontSize: 8, lineHeight: 13, marginTop: 7 },
  save: { minHeight: 50, borderRadius: 13, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 18 },
  saveText: { color: "#050505", fontSize: 10, fontWeight: "900" },
  discard: { minHeight: 42, alignItems: "center", justifyContent: "center", marginTop: 5 },
  discardText: { color: "#9B9BA3", fontSize: 8, fontWeight: "900" },
  disabled: { opacity: 0.45 },
  securityCard: { borderWidth: 1, borderColor: "#303036", borderRadius: 15, backgroundColor: "#08080AB8", padding: 14, marginTop: 12 },
  securityRow: { flexDirection: "row", alignItems: "center", gap: 12 },
  securityTitle: { color: "#FFF", fontSize: 13, fontWeight: "900" },
  securityState: { color: "#9A9AA2", fontSize: 8, fontWeight: "900", marginTop: 4 },
  securityText: { color: "#85858D", fontSize: 10, lineHeight: 16, marginTop: 7 },
  quickButton: { minHeight: 38, borderRadius: 10, borderWidth: 1, borderColor: "#44444B", paddingHorizontal: 12, alignItems: "center", justifyContent: "center" },
  quickButtonActive: { borderColor: "#7A3439", backgroundColor: "#1B090B" },
  quickButtonText: { color: "#D0D0D5", fontSize: 8, fontWeight: "900" },
  quickButtonTextActive: { color: "#FF757B" },
  signOut: { minHeight: 49, borderRadius: 13, borderWidth: 1, borderColor: "#6A292F", backgroundColor: "#180709C7", alignItems: "center", justifyContent: "center", marginTop: 12, marginBottom: 8 },
  signOutText: { color: "#FF7178", fontSize: 10, fontWeight: "900", letterSpacing: 0.6 },
  errorCard: { borderWidth: 1, borderColor: "#4A2429", borderRadius: 16, backgroundColor: "#100708C7", padding: 15, marginTop: 12 },
  errorTitle: { color: "#FFF", fontSize: 14, fontWeight: "900" },
  errorText: { color: "#B98C91", fontSize: 10, lineHeight: 16, marginTop: 7 },
  retry: { minHeight: 44, borderRadius: 11, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 12 },
  retryText: { color: "#050505", fontSize: 9, fontWeight: "900" }
});
