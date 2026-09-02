import { useEffect, useMemo, useState } from "react";
import { SafeAreaView, StyleSheet, Text, TextInput, Pressable, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import Constants from "expo-constants";
import * as SecureStore from "expo-secure-store";
import {
  APP1_PERMISSIONS,
  permissionsForRole,
  type App1Permission,
  type App1Role
} from "@grupo-lua/contracts";

const API_URL = String(
  process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL ||
  Constants.expoConfig?.extra?.apiUrl ||
  "https://cafe-na-ia.onrender.com"
).replace(/\/+$/, "");

const SESSION_KEY = "grupo-lua-app1-probe-session";

type SessionAccount = {
  id: string;
  login: string;
  role: App1Role;
  status: string;
  expires_at?: string;
};

function permissionLabel(permission: App1Permission) {
  if (permission === APP1_PERMISSIONS.SESSION_USE) return "Usar sessão do App 1";
  if (permission === APP1_PERMISSIONS.ADMIN_AREA) return "Área administrativa";
  if (permission === APP1_PERMISSIONS.DEV_PRIVILEGED) return "Ações privilegiadas DEV";
  if (permission === APP1_PERMISSIONS.SOCIAL_PIN_POST) return "Fixar publicação Social (reservado)";
  return permission;
}

export default function App() {
  const [login, setLogin] = useState("");
  const [credential, setCredential] = useState("");
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [account, setAccount] = useState<SessionAccount | null>(null);
  const [result, setResult] = useState("Aguardando teste.");
  const [busy, setBusy] = useState(false);

  const permissions = useMemo(
    () => account ? permissionsForRole(account.role) : [],
    [account]
  );

  useEffect(() => {
    let mounted = true;
    SecureStore.getItemAsync(SESSION_KEY)
      .then(async (token) => {
        if (!mounted || !token) return;
        setSessionToken(token);
        await validateSession(token, mounted);
      })
      .catch(() => {
        if (mounted) setResult("Não foi possível restaurar a sessão local de teste.");
      });
    return () => { mounted = false; };
  }, []);

  async function validateSession(token = sessionToken || "", mounted = true) {
    if (!token) {
      if (mounted) setResult("Nenhuma sessão local para validar.");
      return false;
    }

    try {
      const response = await fetch(`${API_URL}/v1/app1/me`, {
        headers: { authorization: `Bearer ${token}` }
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        await SecureStore.deleteItemAsync(SESSION_KEY);
        if (mounted) {
          setSessionToken(null);
          setAccount(null);
          setResult(`${data.code || "SESSÃO_INVÁLIDA"}: ${data.message || "Sessão recusada"}`);
        }
        return false;
      }

      if (mounted) {
        setAccount(data.account as SessionAccount);
        setResult(`SESSÃO OK • ${data.account.role} • ${data.account.login} • ${data.account.status}`);
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
    setResult("Validando credencial no servidor...");
    try {
      const response = await fetch(`${API_URL}/v1/app1/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ login, credential, deviceLabel: "APP1_PROBE_V0_6" })
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(`${data.code || "ERRO"}: ${data.message || "Falha"}`);

      const token = String(data.token || "");
      if (!token) throw new Error("LOGIN_SEM_SESSÃO: servidor não retornou token.");

      await SecureStore.setItemAsync(SESSION_KEY, token);
      setSessionToken(token);
      setAccount(data.account as SessionAccount);
      setCredential("");
      setResult(`LOGIN OK • ${data.account.role} • sessão salva no armazenamento seguro de teste.`);
      await validateSession(token);
    } catch (error) {
      setCredential("");
      setResult(error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setBusy(false);
    }
  }

  async function clearLocalSession() {
    await SecureStore.deleteItemAsync(SESSION_KEY);
    setSessionToken(null);
    setAccount(null);
    setResult("Sessão removida deste aparelho de teste. Revogação server-side continua sendo controlada pelo Keymaster.");
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.box}>
        <Text style={styles.kicker}>COMPATIBILIDADE APP 1 ↔ KEYMASTER</Text>
        <Text style={styles.title}>Sonda de autenticação</Text>
        <Text style={styles.caption}>
          Esta tela não é o App 1 final. Ela só confirma que contas ADM/DEV criadas pelo Keymaster conseguem autenticar, manter sessão e receber as permissões esperadas.
        </Text>

        <TextInput
          style={styles.input}
          placeholder="Login"
          placeholderTextColor="#666"
          value={login}
          onChangeText={setLogin}
          autoCapitalize="none"
          autoCorrect={false}
        />
        <TextInput
          style={styles.input}
          placeholder="ADMIN APP / DEV KEY"
          placeholderTextColor="#666"
          value={credential}
          onChangeText={setCredential}
          secureTextEntry
          autoCapitalize="none"
          autoCorrect={false}
        />

        <Pressable style={[styles.button, busy && styles.buttonDisabled]} onPress={submit} disabled={busy}>
          <Text style={styles.buttonText}>{busy ? "VALIDANDO..." : "TESTAR LOGIN + SESSÃO"}</Text>
        </Pressable>

        <View style={styles.secondaryRow}>
          <Pressable style={styles.secondaryButton} onPress={() => validateSession()}>
            <Text style={styles.secondaryText}>VALIDAR SESSÃO</Text>
          </Pressable>
          <Pressable style={styles.secondaryButton} onPress={clearLocalSession}>
            <Text style={styles.secondaryText}>LIMPAR LOCAL</Text>
          </Pressable>
        </View>

        <Text style={styles.result}>{result}</Text>

        {account ? (
          <View style={styles.permissionBox}>
            <Text style={styles.permissionTitle}>{account.role} • permissões do contrato</Text>
            {permissions.map((permission) => (
              <Text key={permission} style={styles.permissionItem}>• {permissionLabel(permission)}</Text>
            ))}
            {account.role === "ADM" ? (
              <Text style={styles.guardText}>ADM não recebe permissão DEV nem permissão para fixar publicações.</Text>
            ) : (
              <Text style={styles.guardText}>A permissão Social está apenas reservada no contrato; o Social completo ainda não foi implementado.</Text>
            )}
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#050505", justifyContent: "center", padding: 18 },
  box: { borderWidth: 1, borderColor: "#242424", borderRadius: 22, padding: 20, backgroundColor: "#0A0A0A" },
  kicker: { color: "#777", fontSize: 10, fontWeight: "900", letterSpacing: 1.4 },
  title: { color: "#FFF", fontSize: 27, fontWeight: "900", marginTop: 4 },
  caption: { color: "#8E8E93", fontSize: 12, lineHeight: 18, marginTop: 8, marginBottom: 8 },
  input: { height: 52, backgroundColor: "#111", borderWidth: 1, borderColor: "#2A2A2A", color: "#FFF", borderRadius: 14, paddingHorizontal: 14, marginTop: 10 },
  button: { height: 52, borderRadius: 14, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 14 },
  buttonDisabled: { opacity: 0.55 },
  buttonText: { color: "#050505", fontWeight: "900" },
  secondaryRow: { flexDirection: "row", gap: 8, marginTop: 8 },
  secondaryButton: { flex: 1, minHeight: 46, borderRadius: 12, borderWidth: 1, borderColor: "#2A2A2A", alignItems: "center", justifyContent: "center", paddingHorizontal: 8 },
  secondaryText: { color: "#C5C5CA", fontSize: 11, fontWeight: "800" },
  result: { color: "#AAA", marginTop: 16, lineHeight: 20 },
  permissionBox: { marginTop: 14, padding: 14, borderRadius: 14, backgroundColor: "#101010", borderWidth: 1, borderColor: "#242424" },
  permissionTitle: { color: "#FFF", fontSize: 13, fontWeight: "900", marginBottom: 7 },
  permissionItem: { color: "#B8B8BE", fontSize: 12, lineHeight: 19 },
  guardText: { color: "#7F7F86", fontSize: 11, lineHeight: 16, marginTop: 7 }
});
