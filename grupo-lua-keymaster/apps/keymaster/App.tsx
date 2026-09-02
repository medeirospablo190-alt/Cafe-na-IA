import { useEffect, useState } from "react";
import { ActivityIndicator, SafeAreaView, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import * as LocalAuthentication from "expo-local-authentication";
import { clearSession, readSession, saveSession } from "./src/storage";
import { logoutKeymaster, validateKeymasterSession } from "./src/api";
import { LoginScreen } from "./src/screens/LoginScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { AccountsScreen } from "./src/screens/AccountsScreen";
import { CriticalScreen } from "./src/screens/CriticalScreen";
import { styles } from "./src/styles";

type Screen = "login" | "home" | "accounts" | "critical";

export default function App() {
  const [screen, setScreen] = useState<Screen>("login");
  const [session, setSession] = useState<string | null>(null);
  const [booting, setBooting] = useState(true);

  useEffect(() => {
    (async () => {
      const stored = await readSession();
      if (!stored) return;
      const compatible = await LocalAuthentication.hasHardwareAsync();
      const enrolled = compatible ? await LocalAuthentication.isEnrolledAsync() : false;
      if (!compatible || !enrolled) return;
      const auth = await LocalAuthentication.authenticateAsync({
        promptMessage: "Desbloquear GRUPO LUA KEYMASTER",
        cancelLabel: "Usar chave",
        disableDeviceFallback: false
      });
      if (!auth.success) return;
      try {
        await validateKeymasterSession(stored);
        setSession(stored);
        setScreen("home");
      } catch {
        await clearSession();
      }
    })().finally(() => setBooting(false));
  }, []);

  async function doLogout() {
    if (session) await logoutKeymaster(session).catch(() => {});
    await clearSession();
    setSession(null);
    setScreen("login");
  }

  if (booting) {
    return (
      <SafeAreaView style={styles.root}>
        <StatusBar style="light" />
        <View style={styles.center}><ActivityIndicator size="large" /></View>
      </SafeAreaView>
    );
  }
  if (screen === "login" || !session) {
    return <LoginScreen onAuthenticated={async (token) => {
      await saveSession(token);
      setSession(token);
      setScreen("home");
    }} />;
  }
  if (screen === "accounts") return <AccountsScreen session={session} onBack={() => setScreen("home")} />;
  if (screen === "critical") return <CriticalScreen session={session} onBack={() => setScreen("home")} />;
  return <HomeScreen session={session} onAccounts={() => setScreen("accounts")} onCritical={() => setScreen("critical")} onLogout={doLogout} />;
}
