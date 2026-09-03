import { useEffect, useMemo, useState } from "react";
import { SafeAreaView, ScrollView, StyleSheet, Text, TextInput, Pressable, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import Constants from "expo-constants";
import * as SecureStore from "expo-secure-store";
import {
  APP1_PERMISSIONS,
  permissionsForRole,
  type App1Permission,
  type App1Role
} from "@grupo-lua/contracts";
import { getApp1DeviceIdentity } from "./device";

const API_URL = String(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL ||
  Constants.expoConfig?.extra?.apiUrl ||
  "https://cafe-na-ia.onrender.com"
).replace(/\/+$/, "");

const SESSION_KEY = "grupo-lua-app1-session-v1";
const DEVICE_TOKEN_KEY = "grupo-lua-app1-device-token-v1";

type OnboardingState = {
  completed: boolean;
  termsAccepted: boolean;
  publicNameVerified: boolean;
};

type SessionAccount = {
  profileId: string | null;
  publicName: string | null;
  role: App1Role;
  status: string;
  onboarding: OnboardingState;
};

function permissionLabel(permission: App1Permission) {
  if (permission === APP1_PERMISSIONS.SESSION_USE) return "Usar sessão do App 1";
  if (permission === APP1_PERMISSIONS.ADMIN_AREA) return "Área administrativa";
  if (permission === APP1_PERMISSIONS.DEV_PRIVILEGED) return "Ações privilegiadas DEV";
  if (permission === APP1_PERMISSIONS.SOCIAL_PIN_POST) return "Fixar publicação Social";
  return permission;
}

async function persistSecret(key: string, value: string) {
  await SecureStore.setItemAsync(key, value, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY
  });
}

export default function App() {
  const [login, setLogin] = useState("");
  const [credential, setCredential] = useState("");
  const [publicName, setPublicName] = useState("");
  const [termsChecked, setTermsChecked] = useState(false);
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [deviceToken, setDeviceToken] = useState<string | null>(null);
  const [sessionKind, setSessionKind] = useState<string | null>(null);
  const [account, setAccount] = useState<SessionAccount | null>(null);
  const [result, setResult] = useState("Aguardando teste.");
  const [busy, setBusy] = useState(false);

  const permissions = useMemo(
    () => account ? permissionsForRole(account.role) : [],
    [account]
  );

  useEffect(() => {
    let mounted = true;
    Promise.all([
      SecureStore.getItemAsync(SESSION_KEY),
      SecureStore.getItemAsync(DEVICE_TOKEN_KEY)
    ])
      .then(async ([savedSession, savedDevice]) => {
        if (!mounted) return;
        setSessionToken(savedSession);
        setDeviceToken(savedDevice);
        if (savedSession && savedDevice) {
          await validateSession(savedSession, savedDevice, mounted);
        } else if (savedSession && !savedDevice) {
          setResult("Sessão encontrada sem prova do dispositivo. Um novo login seguro será necessário.");
        }
      })
      .catch(() => {
        if (mounted) setResult("Não foi possível restaurar a sessão segura deste aparelho.");
      });
    return () => { mounted = false; };
  }, []);

  async function validateSession(
    token = sessionToken || "",
    boundDeviceToken = deviceToken || "",
    mounted = true
  ) {
    if (!token || !boundDeviceToken) {
      if (mounted) setResult("Sessão ou prova do dispositivo ausente.");
      return false;
    }

    try {
      const response = await fetch(`${API_URL}/v1/app1/me`, {
        headers: {
          authorization: `Bearer ${token}`,
          "x-app1-device-token": boundDeviceToken
        }
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        await SecureStore.deleteItemAsync(SESSION_KEY);
        if (mounted) {
          setSessionToken(null);
          setSessionKind(null);
          setAccount(null);
          setResult(`${data.code || "SESSÃO_INVÁLIDA"}: ${data.message || "Sessão recusada"}`);
        }
        return false;
      }

      if (mounted) {
        setAccount(data.account as SessionAccount);
        setSessionKind(String(data.session?.kind || ""));
        const name = data.account?.publicName ? ` • ${data.account.publicName}` : "";
        setResult(`SESSÃO OK • ${data.account.role}${name} • ${data.session?.kind || ""}`);
      }
      return true;
    } catch (error) {
      if (mounted) setResult(error instanceof Error ? error.message : "Erro ao validar sessão.");
      return false;
    }
  }

  async function submit() {
    if (!login.trim() || !credential || busy) return;
    setBusy(true);
    setResult("Validando credencial, conta e dispositivo no servidor...");
    try {
      const identity = await getApp1DeviceIdentity();
      const savedDeviceToken = deviceToken || await SecureStore.getItemAsync(DEVICE_TOKEN_KEY) || "";
      const response = await fetch(`${API_URL}/v1/app1/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          login,
          credential,
          deviceLabel: "APP1_PROBE_V0_9",
          ...identity,
          deviceToken: savedDeviceToken
        })
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(`${data.code || "ERRO"}: ${data.message || "Falha"}`);

      const token = String(data.token || "");
      if (!token) throw new Error("LOGIN_SEM_SESSÃO: servidor não retornou token.");

      const issuedDeviceToken = String(data.deviceToken || savedDeviceToken || "");
      if (!issuedDeviceToken) throw new Error("LOGIN_SEM_DISPOSITIVO: servidor não confirmou a prova do dispositivo.");

      await persistSecret(SESSION_KEY, token);
      await persistSecret(DEVICE_TOKEN_KEY, issuedDeviceToken);
      setSessionToken(token);
      setDeviceToken(issuedDeviceToken);
      setSessionKind(String(data.sessionKind || ""));
      setAccount(data.account as SessionAccount);

      // Login e credencial não permanecem na interface depois da autenticação.
      setLogin("");
      setCredential("");
      setResult(
        data.sessionKind === "PROVISIONAL"
          ? "LOGIN OK • conclua os termos e o pseudônimo para iniciar a sessão completa de 24h."
          : "LOGIN OK • sessão completa de 24h validada pelo servidor."
      );
      await validateSession(token, issuedDeviceToken);
    } catch (error) {
      setCredential("");
      setResult(error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setBusy(false);
    }
  }

  async function acceptTerms() {
    if (!termsChecked || !sessionToken || !deviceToken || busy) return;
    setBusy(true);
    setResult("Registrando aceite no servidor...");
    try {
      const response = await fetch(`${API_URL}/v1/app1/onboarding/accept-terms`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${sessionToken}`,
          "x-app1-device-token": deviceToken
        },
        body: JSON.stringify({ accepted: true })
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(`${data.code || "ERRO"}: ${data.message || "Falha"}`);
      setResult("Termos confirmados no servidor. Agora escolha seu pseudônimo.");
      await validateSession(sessionToken, deviceToken);
    } catch (error) {
      setResult(error instanceof Error ? error.message : "Erro ao aceitar os termos.");
    } finally {
      setBusy(false);
    }
  }

  async function confirmPublicName() {
    if (!publicName.trim() || !sessionToken || !deviceToken || busy) return;
    setBusy(true);
    setResult("Validando pseudônimo no servidor...");
    try {
      const response = await fetch(`${API_URL}/v1/app1/onboarding/public-name`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${sessionToken}`,
          "x-app1-device-token": deviceToken
        },
        body: JSON.stringify({ publicName })
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(`${data.code || "ERRO"}: ${data.message || "Falha"}`);
      setPublicName("");
      setAccount(data.account as SessionAccount);
      setSessionKind(String(data.session?.kind || ""));
      setResult(
        data.account?.onboarding?.completed
          ? "ONBOARDING CONCLUÍDO • sessão completa de 24h iniciada."
          : "Nome confirmado. Ainda falta concluir uma etapa do onboarding."
      );
      await validateSession(sessionToken, deviceToken);
    } catch (error) {
      setResult(error instanceof Error ? error.message : "Erro ao confirmar pseudônimo.");
    } finally {
      setBusy(false);
    }
  }

  async function clearLocalSession() {
    await SecureStore.deleteItemAsync(SESSION_KEY);
    setSessionToken(null);
    setSessionKind(null);
    setAccount(null);
    setResult("Sessão removida deste aparelho. A prova do dispositivo foi preservada para o próximo login seguro.");
  }

  const onboarding = account?.onboarding;
  const needsOnboarding = account && !onboarding?.completed;

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
        <View style={styles.box}>
          <Text style={styles.kicker}>APP 1 V1 • SEGURANÇA / COMPATIBILIDADE</Text>
          <Text style={styles.title}>Sonda de autenticação</Text>
          <Text style={styles.caption}>
            Esta tela ainda não é o App 1 final. Ela valida o novo contrato: dispositivo vinculado, onboarding obrigatório e sessão completa de 24 horas sem manter login ou credencial na interface.
          </Text>

          {!sessionToken ? (
            <>
              <TextInput
                style={styles.input}
                placeholder="Login privado"
                placeholderTextColor="#666"
                value={login}
                onChangeText={setLogin}
                autoCapitalize="none"
                autoCorrect={false}
              />
              <TextInput
                style={styles.input}
                placeholder="Chave de acesso"
                placeholderTextColor="#666"
                value={credential}
                onChangeText={setCredential}
                secureTextEntry
                autoCapitalize="none"
                autoCorrect={false}
              />

              <Pressable style={[styles.button, busy && styles.buttonDisabled]} onPress={submit} disabled={busy}>
                <Text style={styles.buttonText}>{busy ? "VALIDANDO..." : "ENTRAR COM SEGURANÇA"}</Text>
              </Pressable>
            </>
          ) : null}

          {needsOnboarding && !onboarding?.termsAccepted ? (
            <View style={styles.onboardingBox}>
              <Text style={styles.sectionTitle}>LEIA COM ATENÇÃO</Text>
              <Text style={styles.caption}>
                Esta sonda só testa o aceite técnico. O App 1 final exibirá o aviso completo aprovado antes de liberar o aplicativo.
              </Text>
              <Pressable style={styles.checkRow} onPress={() => setTermsChecked((value) => !value)}>
                <Text style={styles.check}>{termsChecked ? "☑" : "☐"}</Text>
                <Text style={styles.checkText}>Li e aceito os Termos de Uso, privacidade e segurança.</Text>
              </Pressable>
              <Pressable
                style={[styles.button, (!termsChecked || busy) && styles.buttonDisabled]}
                onPress={acceptTerms}
                disabled={!termsChecked || busy}
              >
                <Text style={styles.buttonText}>CONFIRMAR ACEITE</Text>
              </Pressable>
            </View>
          ) : null}

          {needsOnboarding && onboarding?.termsAccepted && !onboarding?.publicNameVerified ? (
            <View style={styles.onboardingBox}>
              <Text style={styles.sectionTitle}>Escolha seu nome</Text>
              <TextInput
                style={styles.input}
                placeholder="Digite seu pseudônimo..."
                placeholderTextColor="#666"
                value={publicName}
                onChangeText={setPublicName}
                autoCapitalize="words"
                autoCorrect={false}
                maxLength={30}
              />
              <Text style={styles.rules}>
                Regras: 3–30 caracteres • use pseudônimo • não use nome real • não use login ou chave • não use informações pessoais.
              </Text>
              <Pressable
                style={[styles.button, (!publicName.trim() || busy) && styles.buttonDisabled]}
                onPress={confirmPublicName}
                disabled={!publicName.trim() || busy}
              >
                <Text style={styles.buttonText}>CONFIRMAR NOME NO SERVIDOR</Text>
              </Pressable>
            </View>
          ) : null}

          {account?.onboarding?.completed ? (
            <View style={styles.readyBox}>
              <Text style={styles.readyTitle}>ACESSO LIBERADO</Text>
              <Text style={styles.readyText}>
                {account.publicName || "Perfil"} • {account.role} • sessão {sessionKind || "FULL"}
              </Text>
            </View>
          ) : null}

          <View style={styles.secondaryRow}>
            <Pressable style={styles.secondaryButton} onPress={() => validateSession()}>
              <Text style={styles.secondaryText}>VALIDAR SESSÃO</Text>
            </Pressable>
            <Pressable style={styles.secondaryButton} onPress={clearLocalSession}>
              <Text style={styles.secondaryText}>SAIR LOCAL</Text>
            </Pressable>
          </View>

          <Text style={styles.result}>{result}</Text>

          {account ? (
            <View style={styles.permissionBox}>
              <Text style={styles.permissionTitle}>{account.role} • permissões do contrato</Text>
              {permissions.map((permission) => (
                <Text key={permission} style={styles.permissionItem}>• {permissionLabel(permission)}</Text>
              ))}
              <Text style={styles.guardText}>
                Login e chave não são mostrados aqui depois da autenticação. O perfil usa somente a identidade pública aprovada.
              </Text>
            </View>
          ) : null}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#050505" },
  scroll: { flexGrow: 1, justifyContent: "center", padding: 18 },
  box: { borderWidth: 1, borderColor: "#242424", borderRadius: 22, padding: 20, backgroundColor: "#0A0A0A" },
  kicker: { color: "#777", fontSize: 10, fontWeight: "900", letterSpacing: 1.4 },
  title: { color: "#FFF", fontSize: 27, fontWeight: "900", marginTop: 4 },
  caption: { color: "#8E8E93", fontSize: 12, lineHeight: 18, marginTop: 8, marginBottom: 8 },
  input: { height: 52, backgroundColor: "#111", borderWidth: 1, borderColor: "#2A2A2A", color: "#FFF", borderRadius: 14, paddingHorizontal: 14, marginTop: 10, fontSize: 16 },
  button: { minHeight: 52, borderRadius: 14, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 14, paddingHorizontal: 12 },
  buttonDisabled: { opacity: 0.45 },
  buttonText: { color: "#050505", fontWeight: "900", textAlign: "center" },
  secondaryRow: { flexDirection: "row", gap: 8, marginTop: 12 },
  secondaryButton: { flex: 1, minHeight: 46, borderRadius: 12, borderWidth: 1, borderColor: "#2A2A2A", alignItems: "center", justifyContent: "center", paddingHorizontal: 8 },
  secondaryText: { color: "#C5C5CA", fontSize: 11, fontWeight: "800" },
  result: { color: "#AAA", marginTop: 16, lineHeight: 20 },
  onboardingBox: { marginTop: 14, padding: 14, borderRadius: 14, borderWidth: 1, borderColor: "#2A2A2A", backgroundColor: "#0E0E0E" },
  sectionTitle: { color: "#FFF", fontSize: 16, fontWeight: "900" },
  checkRow: { flexDirection: "row", alignItems: "flex-start", gap: 10, paddingVertical: 10 },
  check: { color: "#FFF", fontSize: 22 },
  checkText: { flex: 1, color: "#D0D0D5", lineHeight: 20, paddingTop: 2 },
  rules: { color: "#707078", fontSize: 10, lineHeight: 15, marginTop: 7 },
  readyBox: { marginTop: 14, padding: 14, borderRadius: 14, borderWidth: 1, borderColor: "#303030", backgroundColor: "#111" },
  readyTitle: { color: "#FFF", fontWeight: "900" },
  readyText: { color: "#AAA", marginTop: 5 },
  permissionBox: { marginTop: 14, padding: 14, borderRadius: 14, backgroundColor: "#101010", borderWidth: 1, borderColor: "#242424" },
  permissionTitle: { color: "#FFF", fontSize: 13, fontWeight: "900", marginBottom: 7 },
  permissionItem: { color: "#B8B8BE", fontSize: 12, lineHeight: 19 },
  guardText: { color: "#7F7F86", fontSize: 11, lineHeight: 16, marginTop: 7 }
});
