import { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  ImageBackground,
  Pressable,
  StyleSheet,
  Text,
  View
} from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import AppRootRedesign from "./AppRootRedesign";
import {
  APP1_VERSION,
  checkApp1Compatibility,
  type AppCompatibilityResult
} from "./appVersion";
import { LOGIN_BACKGROUND_DATA_URI } from "./loginBackground";

type GateState = {
  checking: boolean;
  result: AppCompatibilityResult | null;
};

function GateBackground({ children }: { children: React.ReactNode }) {
  return (
    <SafeAreaProvider>
      <ImageBackground source={{ uri: LOGIN_BACKGROUND_DATA_URI }} style={styles.background} resizeMode="cover">
        <View style={styles.shade} pointerEvents="none" />
        <StatusBar style="light" translucent backgroundColor="transparent" />
        <SafeAreaView style={styles.root} edges={["top", "bottom"]}>
          {children}
        </SafeAreaView>
      </ImageBackground>
    </SafeAreaProvider>
  );
}

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
      <GateBackground>
        <View style={styles.center}>
          <ActivityIndicator size="small" color="#FFFFFF" />
        </View>
      </GateBackground>
    );
  }

  if (state.result?.updateRequired) {
    return (
      <GateBackground>
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
      </GateBackground>
    );
  }

  return <AppRootRedesign />;
}

const styles = StyleSheet.create({
  background: { flex: 1, width: "100%", height: "100%" },
  shade: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: "rgba(0,0,0,0.10)"
  },
  root: { flex: 1, backgroundColor: "transparent" },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 20, gap: 10 },
  blockCard: {
    width: "100%",
    maxWidth: 520,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,110,116,0.40)",
    backgroundColor: "rgba(35,7,9,0.52)",
    padding: 18
  },
  eyebrow: { color: "#FF9A9F", fontSize: 11, fontWeight: "900", letterSpacing: 1.1 },
  title: { color: "#FFFFFF", fontSize: 22, lineHeight: 28, fontWeight: "900", marginTop: 7 },
  body: { color: "#F1E4E5", fontSize: 13, lineHeight: 19, marginTop: 8 },
  versionBox: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.24)",
    padding: 12,
    marginTop: 12,
    gap: 4
  },
  versionLine: { color: "#FFFFFF", fontSize: 12, lineHeight: 17, fontWeight: "700" },
  help: { color: "rgba(245,245,248,0.72)", fontSize: 11, lineHeight: 17, marginTop: 11 },
  button: {
    minHeight: 50,
    borderRadius: 12,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#FFFFFF",
    marginTop: 14,
    paddingHorizontal: 16
  },
  buttonText: { color: "#050505", fontSize: 11, fontWeight: "900", letterSpacing: 0.5 }
});
