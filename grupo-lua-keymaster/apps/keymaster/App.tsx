import { useEffect, useState } from "react";
import { ActivityIndicator, SafeAreaView, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import * as LocalAuthentication from "expo-local-authentication";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { clearSession, readSession, saveSession } from "./src/storage";
import { logoutKeymaster, validateKeymasterSession } from "./src/api";
import { LoginScreen } from "./src/screens/LoginScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { AccountsScreen } from "./src/screens/AccountsScreen";
import { MenusScreen } from "./src/screens/MenusScreen";
import { AuditScreen } from "./src/screens/AuditScreen";
import { CriticalScreen } from "./src/screens/CriticalScreen";
import { MenuBaseScreen } from "./src/screens/MenuBaseScreen";
import { styles } from "./src/styles";

type Screen = "login" | "home" | "accounts" | "menus" | "audit" | "critical" | "menuBase";

function KeymasterApp() {
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

  const goHome = () => setScreen("home");
  const goAccounts = () => setScreen("accounts");
  const goMenus = () => setScreen("menus");
  const goAudit = () => setScreen("audit");
  const goCritical = () => setScreen("critical");
  const goMenuBase = () => setScreen("menuBase");

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

  if (screen === "accounts") {
    return <AccountsScreen session={session} onHome={goHome} onMenus={goMenus} onAudit={goAudit} onCritical={goCritical} />;
  }
  if (screen === "menus") {
    return <MenusScreen session={session} onHome={goHome} onAccounts={goAccounts} onAudit={goAudit} onCritical={goCritical} />;
  }
  if (screen === "audit") {
    return <AuditScreen session={session} onHome={goHome} onAccounts={goAccounts} onMenus={goMenus} onCritical={goCritical} />;
  }
  if (screen === "critical") {
    return <CriticalScreen session={session} onHome={goHome} onAccounts={goAccounts} onMenus={goMenus} onAudit={goAudit} />;
  }
  if (screen === "menuBase") {
    return <MenuBaseScreen onBack={goHome} onMenus={goMenus} />;
  }

  return (
    <HomeScreen
      session={session}
      onAccounts={goAccounts}
      onMenus={goMenus}
      onMenuBase={goMenuBase}
      onAudit={goAudit}
      onCritical={goCritical}
      onLogout={doLogout}
    />
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <KeymasterApp />
    </SafeAreaProvider>
  );
}
