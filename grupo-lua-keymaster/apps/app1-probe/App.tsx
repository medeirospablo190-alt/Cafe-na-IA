import { useState } from "react";
import { SafeAreaView, StyleSheet, Text, TextInput, Pressable, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import Constants from "expo-constants";

const API_URL = String(process.env.EXPO_PUBLIC_GRUPO_LUA_API_URL || Constants.expoConfig?.extra?.apiUrl || "https://cafe-na-ia.onrender.com").replace(/\/+$/, "");

export default function App() {
  const [login, setLogin] = useState("");
  const [credential, setCredential] = useState("");
  const [result, setResult] = useState("Aguardando teste.");

  async function submit() {
    setResult("Validando...");
    try {
      const response = await fetch(`${API_URL}/v1/app1/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ login, credential, deviceLabel: "APP1_PROBE" })
      });
      const data = await response.json();
      if (!response.ok) throw new Error(`${data.code || "ERRO"}: ${data.message || "Falha"}`);
      setResult(`OK • ${data.account.role} • ${data.account.login} • ${data.account.status}`);
      setCredential("");
    } catch (error) {
      setResult(error instanceof Error ? error.message : "Erro desconhecido");
      setCredential("");
    }
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.box}>
        <Text style={styles.kicker}>COMPATIBILIDADE APP 1 ↔ KEYMASTER</Text>
        <Text style={styles.title}>Teste de login</Text>
        <TextInput style={styles.input} placeholder="Login" placeholderTextColor="#666" value={login} onChangeText={setLogin} autoCapitalize="none" />
        <TextInput style={styles.input} placeholder="ADMIN APP / DEV KEY" placeholderTextColor="#666" value={credential} onChangeText={setCredential} secureTextEntry autoCapitalize="none" />
        <Pressable style={styles.button} onPress={submit}><Text style={styles.buttonText}>TESTAR ACESSO</Text></Pressable>
        <Text style={styles.result}>{result}</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#050505", justifyContent: "center", padding: 22 },
  box: { borderWidth: 1, borderColor: "#242424", borderRadius: 22, padding: 22, backgroundColor: "#0A0A0A" },
  kicker: { color: "#777", fontSize: 10, fontWeight: "900", letterSpacing: 1.4 },
  title: { color: "#FFF", fontSize: 28, fontWeight: "900", marginTop: 4, marginBottom: 18 },
  input: { height: 52, backgroundColor: "#111", borderWidth: 1, borderColor: "#2A2A2A", color: "#FFF", borderRadius: 14, paddingHorizontal: 14, marginTop: 10 },
  button: { height: 52, borderRadius: 14, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", marginTop: 14 },
  buttonText: { color: "#050505", fontWeight: "900" },
  result: { color: "#AAA", marginTop: 16, lineHeight: 20 }
});
