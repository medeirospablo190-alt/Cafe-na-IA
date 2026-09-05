import { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  View
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import AppRoot from "./AppRoot";
import {
  APP1_VERSION,
  checkApp1Compatibility,
  type AppCompatibilityResult
} from "./appVersion";

type GateState = {
  checking: boolean;
  result: AppCompatibilityResult | null;
};

export default function AppCompatibilityGate() {
  const [state, setState] = useState<GateState>({ checking: true, result: null });
  const warningShown = useRef(false);

  async function refresh() {
    setState((current) => ({ ...current, checking: true }));
    try {
      const result = await checkApp1Compatibility();
      setState({ checking: false, result });
      if (result.status === "UPDATE_AVAILABLE" && !warningShown.current) {
        warningShown.current = true;
        Alert.alert("Atualização disponível", result.message);
      }
    } catch {
      // Compatibilidade não deve transformar uma falha temporária de rede em bloqueio.
      // O AppRoot continua responsável pela tela de configuração, restauração de sessão
      // e mensagens de indisponibilidade já existentes.
      setState({ checking: false, result: null });
    }
  }

  useEffect(() => {
    refresh().catch(() => setState({ checking: false, result: null }));
  }, []);

  if (state.checking) {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SafeAreaView style={styles.root}>
          <View style={styles.center}>
            <Text style={styles.moon}>☾</Text>
            <Text style={styles.brand}>GRUPO LUA</Text>
            <ActivityIndicator size="small" />
            <Text style={styles.muted}>Verificando compatibilidade da versão {APP1_VERSION}...</Text>
          </View>
        </SafeAreaView>
      </SafeAreaProvider>
    );
  }

  if (state.result?.updateRequired) {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <SafeAreaView style={styles.root}>
          <View style={styles.center}>
            <View style={styles.blockCard}>
              <Text style={styles.eyebrow}>ATUALIZAÇÃO NECESSÁRIA</Text>
              <Text style={styles.title}>Esta versão não é mais compatível</Text>
              <Text style={styles.body}>{state.result.message}</Text>
              <View style={styles.versionBox}>
                <Text style={styles.versionLine}>Instalada: {state.result.currentVersion}</Text>
                <Text style={styles.versionLine}>Mínima: {state.result.minSupportedVersion}</Text>
                <Text style={styles.versionLine}>Mais recente: {state.result.latestVersion}</Text>
              </View>
              <Text style={styles.help}>
                O bloqueio protege o login, as chaves e os dados quando a Control API deixa de aceitar uma versão antiga do aplicativo.
              </Text>
              <Pressable style={styles.button} onPress={() => refresh().catch(() => {})}>
                <Text style={styles.buttonText}>VERIFICAR NOVAMENTE</Text>
              </Pressable>
            </View>
          </View>
        </SafeAreaView>
      </SafeAreaProvider>
    );
  }

  return <AppRoot />;
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#030303" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 20, gap: 10 },
  moon: { color: "#D53037", fontSize: 34, fontWeight: "900" },
  brand: { color: "#FFFFFF", fontSize: 22, fontWeight: "900", letterSpacing: 3 },
  muted: { color: "#8B8B92", fontSize: 12, lineHeight: 17, textAlign: "center", marginTop: 4 },
  blockCard: { width: "100%", maxWidth: 520, borderRadius: 18, borderWidth: 1, borderColor: "#5A272C", backgroundColor: "#100708", padding: 18 },
  eyebrow: { color: "#FF737A", fontSize: 11, fontWeight: "900", letterSpacing: 1.1 },
  title: { color: "#FFFFFF", fontSize: 22, lineHeight: 28, fontWeight: "900", marginTop: 7 },
  body: { color: "#D7C6C8", fontSize: 13, lineHeight: 19, marginTop: 8 },
  versionBox: { borderRadius: 12, borderWidth: 1, borderColor: "#3D2A2D", backgroundColor: "#090708", padding: 12, marginTop: 12, gap: 4 },
  versionLine: { color: "#E9E9ED", fontSize: 12, lineHeight: 17, fontWeight: "700" },
  help: { color: "#8F8587", fontSize: 11, lineHeight: 17, marginTop: 11 },
  button: { minHeight: 50, borderRadius: 12, alignItems: "center", justifyContent: "center", backgroundColor: "#FFFFFF", marginTop: 14, paddingHorizontal: 16 },
  buttonText: { color: "#050505", fontSize: 11, fontWeight: "900", letterSpacing: 0.5 }
});
