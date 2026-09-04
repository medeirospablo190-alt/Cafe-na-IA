import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import type { App1Role } from "./api";
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
  onBack
}: {
  sessionToken: string;
  deviceToken: string;
  role: App1Role;
  onBack: () => void;
}) {
  const [profile, setProfile] = useState<PublicProfileView | null>(null);
  const [bio, setBio] = useState("");
  const [statusText, setStatusText] = useState("");
  const [avatarStyle, setAvatarStyle] = useState("MOON");
  const [frameStyle, setFrameStyle] = useState("DEFAULT");
  const [presenceMode, setPresenceMode] = useState<PresenceMode>("VISIBLE");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
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
    try {
      const result = await getOwnProfile(sessionToken, deviceToken);
      if (mounted.current) applyProfile(result.profile);
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Configurações indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar o perfil.");
      }
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

  async function save() {
    if (saving) return;
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

  useEffect(() => {
    mounted.current = true;
    load().catch(() => {});
    return () => { mounted.current = false; };
  }, [sessionToken, deviceToken]);

  if (loading) return <ActivityIndicator style={{ marginVertical: 32 }} />;

  return (
    <View style={s.root}>
      <View style={s.titleRow}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>Perfil e configurações</Text>
          <Text style={s.muted}>Personalização pública e privacidade de presença.</Text>
        </View>
        <Pressable style={s.back} onPress={onBack}><Text style={s.backText}>VOLTAR</Text></Pressable>
      </View>

      <View style={[s.profileCard, role === "DEV" && s.profileDev]}>
        <View style={[s.avatar, frameStyle === "RED" && s.frameRed, frameStyle === "PURPLE" && s.framePurple, frameStyle === "SILVER" && s.frameSilver]}>
          <Text style={s.avatarText}>{(profile?.publicName || "L").slice(0, 1).toUpperCase()}</Text>
        </View>
        <View style={{ flex: 1 }}>
          <View style={s.identityRow}>
            <Text style={s.publicName}>{profile?.publicName || "Perfil"}</Text>
            {role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
          </View>
          <Text style={s.muted}>Pseudônimo confirmado pelo servidor • {role}</Text>
        </View>
      </View>

      <Text style={s.label}>PENSAMENTO / STATUS</Text>
      <TextInput
        value={statusText}
        onChangeText={setStatusText}
        maxLength={80}
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
        style={[s.input, s.bio]}
        placeholder="Uma descrição curta do seu perfil..."
        placeholderTextColor="#626269"
        textAlignVertical="top"
      />
      <Text style={s.counter}>{Array.from(bio).length}/280</Text>

      <Text style={s.label}>AVATAR</Text>
      <View style={s.choices}>
        {AVATARS.map((item) => (
          <Pressable key={item} style={[s.choice, avatarStyle === item && s.choiceActive]} onPress={() => setAvatarStyle(item)}>
            <Text style={[s.choiceText, avatarStyle === item && s.choiceTextActive]}>{labelForAvatar(item)}</Text>
          </Pressable>
        ))}
      </View>

      <Text style={s.label}>MOLDURA</Text>
      <View style={s.choices}>
        {FRAMES.map((item) => (
          <Pressable key={item} style={[s.choice, frameStyle === item && s.choiceActive]} onPress={() => setFrameStyle(item)}>
            <Text style={[s.choiceText, frameStyle === item && s.choiceTextActive]}>{labelForFrame(item)}</Text>
          </Pressable>
        ))}
      </View>

      <Text style={s.label}>PRESENÇA</Text>
      <View style={s.choices}>
        <Pressable style={[s.choice, presenceMode === "VISIBLE" && s.choiceActive]} onPress={() => setPresenceMode("VISIBLE")}>
          <Text style={[s.choiceText, presenceMode === "VISIBLE" && s.choiceTextActive]}>VISÍVEL</Text>
        </Pressable>
        <Pressable style={[s.choice, presenceMode === "HIDDEN" && s.choiceActive]} onPress={() => setPresenceMode("HIDDEN")}>
          <Text style={[s.choiceText, presenceMode === "HIDDEN" && s.choiceTextActive]}>OCULTA</Text>
        </Pressable>
      </View>

      <Pressable style={[s.save, saving && s.disabled]} disabled={saving} onPress={save}>
        <Text style={s.saveText}>{saving ? "SALVANDO..." : "SALVAR CONFIGURAÇÕES"}</Text>
      </Pressable>

      <View style={s.securityCard}>
        <Text style={s.securityTitle}>Privacidade e segurança</Text>
        <Text style={s.securityText}>
          Login privado, chave, dispositivos autorizados, role real e bloqueios de segurança não podem ser alterados pelo perfil. Chats privados não possuem leitura administrativa comum enquanto a conta estiver ativa.
        </Text>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  titleRow: { flexDirection: "row", alignItems: "center", gap: 10, marginBottom: 12 },
  title: { color: "#FFF", fontSize: 22, fontWeight: "900" },
  muted: { color: "#77777F", fontSize: 10, lineHeight: 15, marginTop: 3 },
  back: { borderWidth: 1, borderColor: "#303036", borderRadius: 10, paddingHorizontal: 11, paddingVertical: 9 },
  backText: { color: "#BDBDC4", fontSize: 8, fontWeight: "900" },
  profileCard: { flexDirection: "row", alignItems: "center", gap: 12, borderRadius: 18, borderWidth: 1, borderColor: "#292930", backgroundColor: "#09090C", padding: 14, marginBottom: 14 },
  profileDev: { borderColor: "#4B2024" },
  avatar: { width: 48, height: 48, borderRadius: 24, borderWidth: 2, borderColor: "#45454D", backgroundColor: "#16161A", alignItems: "center", justifyContent: "center" },
  frameRed: { borderColor: "#E24A52" },
  framePurple: { borderColor: "#B47AE8" },
  frameSilver: { borderColor: "#D0D0D5" },
  avatarText: { color: "#FFF", fontSize: 18, fontWeight: "900" },
  identityRow: { flexDirection: "row", alignItems: "center", gap: 7 },
  publicName: { color: "#FFF", fontSize: 15, fontWeight: "900" },
  devBadge: { color: "#FF686F", fontSize: 8, fontWeight: "900", backgroundColor: "#210A0C", borderRadius: 6, paddingHorizontal: 6, paddingVertical: 3 },
  label: { color: "#76767E", fontSize: 9, fontWeight: "900", letterSpacing: 1.1, marginTop: 12 },
  input: { minHeight: 49, borderRadius: 13, borderWidth: 1, borderColor: "#2C2C32", backgroundColor: "#101013", color: "#FFF", paddingHorizontal: 13, marginTop: 7 },
  bio: { minHeight: 105, paddingTop: 12, paddingBottom: 12 },
  counter: { color: "#606067", fontSize: 8, textAlign: "right", marginTop: 4 },
  choices: { flexDirection: "row", flexWrap: "wrap", gap: 7, marginTop: 7 },
  choice: { borderWidth: 1, borderColor: "#313138", borderRadius: 10, paddingHorizontal: 11, paddingVertical: 9 },
  choiceActive: { backgroundColor: "#FFF", borderColor: "#FFF" },
  choiceText: { color: "#8B8B93", fontSize: 8, fontWeight: "900" },
  choiceTextActive: { color: "#070708" },
  save: { minHeight: 50, borderRadius: 13, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 18 },
  saveText: { color: "#050505", fontSize: 10, fontWeight: "900" },
  disabled: { opacity: 0.45 },
  securityCard: { borderWidth: 1, borderColor: "#27272D", borderRadius: 16, backgroundColor: "#08080A", padding: 14, marginTop: 13 },
  securityTitle: { color: "#FFF", fontSize: 13, fontWeight: "900" },
  securityText: { color: "#74747C", fontSize: 10, lineHeight: 16, marginTop: 6 }
});
