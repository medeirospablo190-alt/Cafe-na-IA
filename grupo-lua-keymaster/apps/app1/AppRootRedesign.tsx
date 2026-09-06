import { useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  ImageBackground,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import { StatusBar } from "expo-status-bar";
import * as SecureStore from "expo-secure-store";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import {
  acceptTerms,
  App1ApiError,
  confirmPublicName,
  getMe,
  loginApp1,
  type App1Session,
  type PublicAccount
} from "./api";
import { API_URL } from "./config";
import { getApp1DeviceIdentity } from "./device";
import { FilesScreen } from "./FilesScreen";
import { KeysScreen } from "./KeysScreen";
import { ChatsScreen } from "./ChatsScreen";
import { SettingsScreen } from "./SettingsScreen";
import { logoutApp1 } from "./session-api";
import { SocialFeedScreen } from "./SocialFeedScreen";
import { DevUpdatesHome } from "./DevUpdatesHome";
import {
  authenticateForQuickUnlock,
  isQuickUnlockEnabled,
  markQuickUnlockOfferShown,
  setQuickUnlockEnabled,
  shouldOfferQuickUnlock
} from "./quickUnlock";
import { LOGIN_BACKGROUND_DATA_URI } from "./loginBackground";

const SESSION_KEY = "grupo-lua-app1-session-v1";
const DEVICE_TOKEN_KEY = "grupo-lua-app1-device-token-v1";

type Tab = "home" | "files" | "social" | "keys" | "settings";
type SocialSection = "feed" | "chat";
type NavIconName = "home" | "files" | "social" | "keys" | "settings";

type NoticeSection = {
  title: string;
  text: string;
  emphasis?: string;
};

const NOTICE_SECTIONS: NoticeSection[] = [
  {
    title: "Social e mensagens",
    text: "Posts e conversas normais da área Social são temporários e podem ser removidos automaticamente após 24 horas. Conteúdos preservados pelas funções do aplicativo, como favoritos, podem permanecer disponíveis por mais tempo."
  },
  {
    title: "Notificações",
    text: "Notificações de curtidas, comentários, favoritos e mensagens são temporárias e são removidas após 24 horas."
  },
  {
    title: "Chaves, menus e outros dados",
    text: "A regra de 24 horas é aplicada à área Social e às mensagens. Chaves, menus, scripts, configurações e outros dados administrativos não são apagados por essa regra."
  },
  {
    title: "Privacidade das conversas",
    text: "Enquanto sua conta estiver ativa, suas conversas privadas não ficam disponíveis para visualização administrativa comum. Denúncias podem preservar somente o conteúdo necessário para análise auditada."
  },
  {
    title: "Proteja seu acesso",
    text: "Não compartilhe o aplicativo, seu login, sua chave de acesso ou sua sessão. Tentativas incorretas podem acionar os bloqueios de segurança do servidor."
  },
  {
    title: "Outro celular ou dispositivo",
    text: "Sua conta é vinculada aos dispositivos autorizados. Para trocar ou adicionar outro celular, use o fluxo administrativo correto antes de tentar entrar no novo aparelho."
  },
  {
    title: "Identidade e privacidade pessoal",
    text: "Use pseudônimos no aplicativo e evite publicar informações reais que identifiquem você ou terceiros.",
    emphasis: "Não utilize seu login, sua chave ou outra informação de autenticação como nome público."
  }
];

async function saveSecure(key: string, value: string) {
  await SecureStore.setItemAsync(key, value, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY
  });
}

function readableError(error: unknown) {
  if (error instanceof App1ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return "Não foi possível concluir esta operação.";
}

function sessionIsDefinitelyInvalid(error: unknown) {
  return error instanceof App1ApiError && (error.status === 401 || error.status === 403);
}

export default function AppRootRedesign() {
  const [booting, setBooting] = useState(true);
  const [busy, setBusy] = useState(false);
  const [login, setLogin] = useState("");
  const [credential, setCredential] = useState("");
  const [sessionToken, setSessionToken] = useState<string | null>(null);
  const [deviceToken, setDeviceToken] = useState<string | null>(null);
  const [session, setSession] = useState<App1Session | null>(null);
  const [account, setAccount] = useState<PublicAccount | null>(null);
  const [termsChecked, setTermsChecked] = useState(false);
  const [publicName, setPublicName] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("home");
  const [sessionRecoveryPending, setSessionRecoveryPending] = useState(false);
  const [quickUnlockPending, setQuickUnlockPending] = useState(false);
  const signOutLock = useRef(false);
  const recoveryLock = useRef(false);
  const unlockLock = useRef(false);

  const onboarding = account?.onboarding;
  const authenticated = Boolean(sessionToken && deviceToken && account);
  const appUnlocked = Boolean(authenticated && onboarding?.completed && session?.kind === "FULL");

  useEffect(() => {
    let active = true;
    Promise.all([
      SecureStore.getItemAsync(SESSION_KEY),
      SecureStore.getItemAsync(DEVICE_TOKEN_KEY),
      isQuickUnlockEnabled().catch(() => false)
    ])
      .then(async ([savedSession, savedDevice, quickEnabled]) => {
        if (!active) return;
        setSessionToken(savedSession);
        setDeviceToken(savedDevice);
        if (!savedSession || !savedDevice) return;
        if (quickEnabled) {
          setQuickUnlockPending(true);
          return;
        }
        await restoreSession(savedSession, savedDevice, active);
      })
      .catch(() => {
        if (active) setMessage("Não foi possível ler a sessão segura deste aparelho.");
      })
      .finally(() => {
        if (active) setBooting(false);
      });

    return () => {
      active = false;
    };
  }, []);

  async function restoreSession(savedSession: string, savedDevice: string, active = true) {
    try {
      const result = await getMe(savedSession, savedDevice);
      if (!active) return true;
      setAccount(result.account);
      setSession(result.session);
      setSessionRecoveryPending(false);
      setQuickUnlockPending(false);
      setMessage(null);
      return true;
    } catch (error) {
      if (sessionIsDefinitelyInvalid(error)) {
        await SecureStore.deleteItemAsync(SESSION_KEY).catch(() => {});
        await setQuickUnlockEnabled(false).catch(() => {});
        if (active) {
          setSessionToken(null);
          setSession(null);
          setAccount(null);
          setSessionRecoveryPending(false);
          setQuickUnlockPending(false);
          setMessage("A sessão salva expirou ou foi revogada. Entre novamente para continuar.");
        }
      } else if (active) {
        setSession(null);
        setAccount(null);
        setSessionRecoveryPending(true);
        setQuickUnlockPending(false);
        setMessage(`A sessão continua salva neste aparelho, mas o servidor não pôde confirmá-la agora. ${readableError(error)}`);
      }
      return false;
    }
  }

  async function unlockStoredSession() {
    if (!sessionToken || !deviceToken || unlockLock.current) return;
    unlockLock.current = true;
    setBusy(true);
    setMessage(null);
    try {
      const result = await authenticateForQuickUnlock();
      if (!result.ok) {
        setMessage(result.message);
        return;
      }
      await restoreSession(sessionToken, deviceToken, true);
    } finally {
      unlockLock.current = false;
      setBusy(false);
    }
  }

  function confirmUseLoginInstead() {
    if (busy) return;
    Alert.alert(
      "Usar login novamente?",
      "A sessão salva neste aparelho será descartada localmente. A autorização do dispositivo não será removida do servidor.",
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Usar login", style: "destructive", onPress: () => { discardStoredSession().catch(() => {}); } }
      ]
    );
  }

  async function retryStoredSession() {
    if (!sessionToken || !deviceToken || recoveryLock.current) return;
    recoveryLock.current = true;
    setBusy(true);
    setMessage("Confirmando a sessão salva...");
    try {
      await restoreSession(sessionToken, deviceToken, true);
    } finally {
      recoveryLock.current = false;
      setBusy(false);
    }
  }

  async function discardStoredSession() {
    if (recoveryLock.current) return;
    recoveryLock.current = true;
    setBusy(true);
    try {
      await clearLocalSession("Sessão salva descartada neste aparelho. Faça login novamente para continuar.");
    } finally {
      recoveryLock.current = false;
      setBusy(false);
    }
  }

  async function activateQuickUnlockFromOffer() {
    try {
      const authentication = await authenticateForQuickUnlock();
      if (!authentication.ok) {
        Alert.alert("Não foi possível ativar", authentication.message);
        return;
      }
      await setQuickUnlockEnabled(true);
      Alert.alert(
        "Acesso rápido ativado",
        "Nas próximas aberturas, o GRUPO LUA pedirá a proteção do próprio celular antes de liberar a sessão salva. Sua chave de login não é armazenada para isso."
      );
    } catch (error) {
      Alert.alert("Falha", readableError(error));
    }
  }

  async function offerQuickUnlockAfterLogin() {
    try {
      if (!(await shouldOfferQuickUnlock())) return;
      await markQuickUnlockOfferShown();
      Alert.alert(
        "Ativar acesso rápido?",
        "Você pode usar biometria ou a proteção oferecida pelo próprio celular para liberar esta sessão nas próximas aberturas. A senha/chave da conta não será salva.",
        [
          { text: "Agora não", style: "cancel" },
          { text: "Ativar", onPress: () => { activateQuickUnlockFromOffer().catch(() => {}); } }
        ]
      );
    } catch {
      // O login continua normal se o armazenamento local estiver indisponível.
    }
  }

  async function submitLogin() {
    if (!login.trim() || !credential || busy) return;
    setBusy(true);
    setMessage(null);
    try {
      const identity = await getApp1DeviceIdentity();
      const savedDevice = deviceToken || await SecureStore.getItemAsync(DEVICE_TOKEN_KEY) || "";
      const result = await loginApp1(login.trim(), credential, identity, savedDevice);
      const issuedDeviceToken = String(result.deviceToken || savedDevice || "");
      if (!issuedDeviceToken) throw new Error("O servidor não confirmou este dispositivo.");

      await saveSecure(SESSION_KEY, result.token);
      await saveSecure(DEVICE_TOKEN_KEY, issuedDeviceToken);
      setSessionToken(result.token);
      setDeviceToken(issuedDeviceToken);
      setSession({ kind: result.sessionKind, expiresAt: result.expiresAt });
      setAccount(result.account);
      setSessionRecoveryPending(false);
      setQuickUnlockPending(false);
      setLogin("");
      setCredential("");
      setTermsChecked(false);
      setPublicName("");
      offerQuickUnlockAfterLogin().catch(() => {});
    } catch (error) {
      setCredential("");
      Alert.alert("Login", readableError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitTerms() {
    if (!termsChecked || !sessionToken || !deviceToken || busy) return;
    setBusy(true);
    setMessage(null);
    try {
      await acceptTerms(sessionToken, deviceToken);
      await restoreSession(sessionToken, deviceToken);
      setTermsChecked(false);
    } catch (error) {
      setMessage(readableError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitPublicName() {
    if (!sessionToken || !deviceToken || busy) return;
    const name = publicName.trim();
    if (Array.from(name).length < 3) {
      setMessage("Escolha um pseudônimo com pelo menos 3 caracteres.");
      return;
    }

    setBusy(true);
    setMessage(null);
    try {
      const result = await confirmPublicName(sessionToken, deviceToken, name);
      setAccount(result.account);
      setSession(result.session);
      setSessionRecoveryPending(false);
      setPublicName("");
      setTab("home");
    } catch (error) {
      setMessage(readableError(error));
    } finally {
      setBusy(false);
    }
  }

  async function clearLocalSession(messageText: string) {
    await Promise.all([
      SecureStore.deleteItemAsync(SESSION_KEY).catch(() => {}),
      setQuickUnlockEnabled(false).catch(() => {})
    ]);
    setSessionToken(null);
    setSession(null);
    setAccount(null);
    setSessionRecoveryPending(false);
    setQuickUnlockPending(false);
    setLogin("");
    setCredential("");
    setTermsChecked(false);
    setPublicName("");
    setTab("home");
    setMessage(messageText);
  }

  async function signOutLocal() {
    if (!sessionToken || !deviceToken || signOutLock.current) return;
    signOutLock.current = true;
    setMessage(null);
    try {
      await logoutApp1(sessionToken, deviceToken);
      await clearLocalSession("Sessão encerrada no servidor e removida deste aparelho. A autorização do dispositivo foi preservada.");
    } catch (error) {
      if (sessionIsDefinitelyInvalid(error)) {
        await clearLocalSession("A sessão já não era válida no servidor e foi removida deste aparelho.");
      } else {
        setMessage(`Não foi possível confirmar o encerramento no servidor: ${readableError(error)} A sessão foi mantida neste aparelho para você tentar novamente.`);
      }
    } finally {
      signOutLock.current = false;
    }
  }

  const body = useMemo(() => {
    if (booting) return <BootScreen />;
    if (!API_URL) return <ConfigurationScreen />;
    if (quickUnlockPending && sessionToken && deviceToken) {
      return (
        <QuickUnlockScreen
          busy={busy}
          message={message}
          onUnlock={unlockStoredSession}
          onUseLogin={confirmUseLoginInstead}
        />
      );
    }
    if (sessionRecoveryPending && sessionToken && deviceToken) {
      return (
        <SessionRecoveryScreen
          busy={busy}
          message={message}
          onRetry={retryStoredSession}
          onDiscard={confirmUseLoginInstead}
        />
      );
    }
    if (!authenticated) {
      return (
        <LoginScreen
          login={login}
          credential={credential}
          busy={busy}
          onLogin={setLogin}
          onCredential={setCredential}
          onSubmit={submitLogin}
        />
      );
    }
    if (!onboarding?.termsAccepted) {
      return (
        <TermsScreen
          checked={termsChecked}
          busy={busy}
          message={message}
          onToggle={() => setTermsChecked((value) => !value)}
          onContinue={submitTerms}
        />
      );
    }
    if (!onboarding.publicNameVerified || !onboarding.completed) {
      return (
        <NameScreen
          value={publicName}
          busy={busy}
          message={message}
          onChange={setPublicName}
          onSubmit={submitPublicName}
        />
      );
    }
    if (appUnlocked && account && sessionToken && deviceToken) {
      return (
        <HomeShell
          account={account}
          sessionToken={sessionToken}
          deviceToken={deviceToken}
          sessionExpiresAt={session?.expiresAt || ""}
          tab={tab}
          onTab={setTab}
          onSignOut={signOutLocal}
        />
      );
    }
    return <BootScreen />;
  }, [
    booting,
    authenticated,
    onboarding?.termsAccepted,
    onboarding?.publicNameVerified,
    onboarding?.completed,
    appUnlocked,
    sessionRecoveryPending,
    quickUnlockPending,
    login,
    credential,
    busy,
    message,
    termsChecked,
    publicName,
    account,
    sessionToken,
    deviceToken,
    session?.expiresAt,
    tab
  ]);

  return (
    <SafeAreaProvider>
      <ImageBackground source={{ uri: LOGIN_BACKGROUND_DATA_URI }} style={styles.background} resizeMode="cover">
        <View style={styles.globalShade} pointerEvents="none" />
        <StatusBar style="light" />
        <SafeAreaView style={styles.safeArea} edges={["top", "bottom"]}>
          {body}
        </SafeAreaView>
      </ImageBackground>
    </SafeAreaProvider>
  );
}

function BootScreen() {
  return (
    <View style={styles.center}>
      <ActivityIndicator size="small" color="#FFFFFF" />
    </View>
  );
}

function ConfigurationScreen() {
  return (
    <View style={styles.center}>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Servidor não configurado</Text>
        <Text style={styles.paragraph}>Esta build ainda não recebeu o endereço da Control API.</Text>
      </View>
    </View>
  );
}

function QuickUnlockScreen({
  busy,
  message,
  onUnlock,
  onUseLogin
}: {
  busy: boolean;
  message: string | null;
  onUnlock: () => void;
  onUseLogin: () => void;
}) {
  return (
    <View style={styles.center}>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Confirme no celular</Text>
        <Text style={styles.paragraph}>Use a proteção do próprio aparelho para liberar a sessão salva.</Text>
        {message ? <Text style={styles.error}>{message}</Text> : null}
        <PrimaryButton title="LIBERAR" onPress={onUnlock} disabled={busy} busy={busy} />
        <Pressable style={styles.textButton} onPress={onUseLogin} disabled={busy}>
          <Text style={styles.textButtonLabel}>USAR LOGIN NOVAMENTE</Text>
        </Pressable>
      </View>
    </View>
  );
}

function SessionRecoveryScreen({
  busy,
  message,
  onRetry,
  onDiscard
}: {
  busy: boolean;
  message: string | null;
  onRetry: () => void;
  onDiscard: () => void;
}) {
  return (
    <View style={styles.center}>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Sessão preservada</Text>
        <Text style={styles.paragraph}>A sessão continua salva porque uma falha temporária de rede não deve apagar seu acesso local.</Text>
        {message ? <Text style={styles.error}>{message}</Text> : null}
        <PrimaryButton title="TENTAR NOVAMENTE" onPress={onRetry} disabled={busy} busy={busy} />
        <Pressable style={styles.textButton} onPress={onDiscard} disabled={busy}>
          <Text style={styles.textButtonLabel}>USAR LOGIN</Text>
        </Pressable>
      </View>
    </View>
  );
}

function LoginScreen({
  login,
  credential,
  busy,
  onLogin,
  onCredential,
  onSubmit
}: {
  login: string;
  credential: string;
  busy: boolean;
  onLogin: (value: string) => void;
  onCredential: (value: string) => void;
  onSubmit: () => void;
}) {
  return (
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === "ios" ? "padding" : "height"}>
      <View style={styles.loginWrap}>
        <View style={styles.loginCard}>
          <TextInput
            value={login}
            onChangeText={onLogin}
            placeholder="Login"
            placeholderTextColor="rgba(255,255,255,0.70)"
            style={styles.loginInput}
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="username"
          />
          <TextInput
            value={credential}
            onChangeText={onCredential}
            placeholder="Chave"
            placeholderTextColor="rgba(255,255,255,0.70)"
            style={styles.loginInput}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="password"
          />
          <Pressable
            style={[styles.loginButton, (busy || !login.trim() || !credential) && styles.disabled]}
            onPress={onSubmit}
            disabled={busy || !login.trim() || !credential}
          >
            {busy ? <ActivityIndicator size="small" color="#050505" style={styles.loginSpinner} /> : null}
            <Text style={styles.loginButtonText}>ENTRAR</Text>
          </Pressable>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

function TermsScreen({
  checked,
  busy,
  message,
  onToggle,
  onContinue
}: {
  checked: boolean;
  busy: boolean;
  message: string | null;
  onToggle: () => void;
  onContinue: () => void;
}) {
  return (
    <ScrollView contentContainerStyle={styles.onboardingScroll}>
      <View style={styles.warningCard}>
        <Text style={styles.warningTitle}>Leia com atenção</Text>
        <Text style={styles.paragraph}>Informações importantes sobre privacidade, retenção de dados e segurança da sua conta.</Text>
      </View>
      {NOTICE_SECTIONS.map((section) => (
        <View key={section.title} style={styles.termSection}>
          <Text style={styles.termTitle}>{section.title}</Text>
          <Text style={styles.paragraph}>{section.text}</Text>
          {section.emphasis ? <Text style={styles.termEmphasis}>{section.emphasis}</Text> : null}
        </View>
      ))}
      <Pressable style={styles.checkRow} onPress={onToggle} accessibilityRole="checkbox" accessibilityState={{ checked }}>
        <Text style={styles.checkIcon}>{checked ? "☑" : "☐"}</Text>
        <Text style={styles.checkText}>Li e aceito os Termos de Uso, as regras de privacidade e as regras de segurança do GRUPO LUA.</Text>
      </Pressable>
      {message ? <Text style={styles.error}>{message}</Text> : null}
      <PrimaryButton title="CONTINUAR" onPress={onContinue} disabled={!checked || busy} busy={busy} />
    </ScrollView>
  );
}

function NameScreen({
  value,
  busy,
  message,
  onChange,
  onSubmit
}: {
  value: string;
  busy: boolean;
  message: string | null;
  onChange: (value: string) => void;
  onSubmit: () => void;
}) {
  const length = Array.from(value.trim()).length;
  return (
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === "ios" ? "padding" : "height"}>
      <ScrollView contentContainerStyle={styles.nameScroll} keyboardShouldPersistTaps="handled">
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Escolha seu nome</Text>
          <Text style={styles.paragraph}>Use um pseudônimo de 3 a 30 caracteres. Não use login, chave ou informações pessoais.</Text>
          <TextInput
            value={value}
            onChangeText={onChange}
            placeholder="Seu pseudônimo..."
            placeholderTextColor="rgba(235,235,240,0.55)"
            style={styles.input}
            autoCapitalize="words"
            autoCorrect={false}
            maxLength={30}
          />
          <Text style={styles.counter}>{length}/30</Text>
          {message ? <Text style={styles.error}>{message}</Text> : null}
          <PrimaryButton title="CONFIRMAR NOME" onPress={onSubmit} disabled={busy || length < 3 || length > 30} busy={busy} />
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function HomeShell({
  account,
  sessionToken,
  deviceToken,
  sessionExpiresAt,
  tab,
  onTab,
  onSignOut
}: {
  account: PublicAccount;
  sessionToken: string;
  deviceToken: string;
  sessionExpiresAt: string;
  tab: Tab;
  onTab: (tab: Tab) => void;
  onSignOut: () => void;
}) {
  const [socialSection, setSocialSection] = useState<SocialSection>("feed");

  function openTab(next: Tab) {
    if (next === "social") setSocialSection("feed");
    onTab(next);
  }

  return (
    <View style={styles.appShell}>
      <ScrollView
        style={styles.appScroll}
        contentContainerStyle={styles.appContent}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        {tab === "home" ? (
          <DevUpdatesHome
            sessionToken={sessionToken}
            deviceToken={deviceToken}
            viewerRole={account.role}
          />
        ) : tab === "files" ? (
          <FilesScreen sessionToken={sessionToken} deviceToken={deviceToken} profileId={account.profileId} />
        ) : tab === "social" ? (
          socialSection === "feed" ? (
            <SocialFeedScreen
              sessionToken={sessionToken}
              deviceToken={deviceToken}
              viewerProfileId={account.profileId}
              viewerPublicName={account.publicName || "Lua"}
              viewerRole={account.role}
              sessionExpiresAt={sessionExpiresAt}
              onOpenChat={() => setSocialSection("chat")}
              onOpenProfile={() => onTab("settings")}
            />
          ) : (
            <>
              <View style={styles.chatHeader}>
                <Pressable style={styles.chatBack} onPress={() => setSocialSection("feed")}>
                  <Text style={styles.chatBackText}>‹</Text>
                </Pressable>
                <Text style={styles.chatTitle}>Chat</Text>
                <View style={styles.chatHeaderSpacer} />
                <Pressable style={styles.profileMiniButton} onPress={() => onTab("settings")}>
                  <View style={styles.profileMiniHead} />
                  <View style={styles.profileMiniShoulders} />
                </Pressable>
              </View>
              <ChatsScreen sessionToken={sessionToken} deviceToken={deviceToken} />
            </>
          )
        ) : tab === "keys" ? (
          <KeysScreen sessionToken={sessionToken} deviceToken={deviceToken} />
        ) : (
          <SettingsScreen
            sessionToken={sessionToken}
            deviceToken={deviceToken}
            role={account.role}
            onSignOut={onSignOut}
          />
        )}
      </ScrollView>

      <View style={styles.bottomNav}>
        <NavItem icon="home" label="Início" active={tab === "home"} onPress={() => openTab("home")} />
        <NavItem icon="files" label="Arquivos" active={tab === "files"} onPress={() => openTab("files")} />
        <NavItem icon="social" label="Social" active={tab === "social"} onPress={() => openTab("social")} />
        <NavItem icon="keys" label="Chaves" active={tab === "keys"} onPress={() => openTab("keys")} />
        <NavItem icon="settings" label="Config." active={tab === "settings"} onPress={() => openTab("settings")} />
      </View>
    </View>
  );
}

function NavGlyph({ icon, active }: { icon: NavIconName; active: boolean }) {
  const tint = active ? "#FFFFFF" : "rgba(235,235,240,0.62)";
  const accent = active ? "#FF2638" : "transparent";

  if (icon === "home") {
    return (
      <View style={styles.navGlyphBox}>
        <View style={[styles.homeRoof, { borderColor: tint }]} />
        <View style={[styles.homeBody, { borderColor: tint }]} />
      </View>
    );
  }

  if (icon === "files") {
    return (
      <View style={styles.navGlyphBox}>
        <View style={[styles.folderBody, { borderColor: tint }]}>
          <View style={[styles.folderTab, { borderColor: tint }]} />
        </View>
      </View>
    );
  }

  if (icon === "social") {
    return (
      <View style={styles.navGlyphBox}>
        <View style={[styles.socialSquare, { borderColor: active ? "#FF2638" : tint, backgroundColor: accent }]} />
      </View>
    );
  }

  if (icon === "keys") {
    return (
      <View style={styles.navGlyphBox}>
        <View style={[styles.keyRing, { borderColor: tint }]} />
        <View style={[styles.keyShaft, { backgroundColor: tint }]} />
        <View style={[styles.keyToothA, { backgroundColor: tint }]} />
        <View style={[styles.keyToothB, { backgroundColor: tint }]} />
      </View>
    );
  }

  return (
    <View style={styles.navGlyphBox}>
      <View style={[styles.settingsRing, { borderColor: tint }]}>
        <View style={[styles.settingsCore, { borderColor: tint }]} />
      </View>
      <View style={[styles.settingsSpokeTop, { backgroundColor: tint }]} />
      <View style={[styles.settingsSpokeBottom, { backgroundColor: tint }]} />
      <View style={[styles.settingsSpokeLeft, { backgroundColor: tint }]} />
      <View style={[styles.settingsSpokeRight, { backgroundColor: tint }]} />
    </View>
  );
}

function NavItem({
  icon,
  label,
  active,
  onPress
}: {
  icon: NavIconName;
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable style={styles.navItem} onPress={onPress} accessibilityRole="button" accessibilityLabel={label}>
      <NavGlyph icon={icon} active={active} />
      <Text style={[styles.navText, active && styles.navTextActive]}>{label}</Text>
    </Pressable>
  );
}

function PrimaryButton({
  title,
  onPress,
  disabled,
  busy
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  busy?: boolean;
}) {
  return (
    <Pressable style={[styles.primaryButton, disabled && styles.disabled]} onPress={onPress} disabled={disabled}>
      {busy ? <ActivityIndicator size="small" color="#050505" style={styles.primarySpinner} /> : null}
      <Text style={styles.primaryButtonText}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  background: { flex: 1, width: "100%", height: "100%" },
  globalShade: {
    position: "absolute",
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: "rgba(0,0,0,0.10)"
  },
  safeArea: { flex: 1, backgroundColor: "transparent" },
  flex: { flex: 1 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 18 },
  card: {
    width: "100%",
    maxWidth: 520,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(5,5,7,0.34)",
    padding: 16
  },
  cardTitle: { color: "#FFFFFF", fontSize: 19, fontWeight: "900", marginBottom: 7 },
  paragraph: { color: "rgba(240,240,244,0.78)", fontSize: 12, lineHeight: 18 },
  error: { color: "#FF8A90", fontSize: 11, lineHeight: 17, marginTop: 10 },
  textButton: { minHeight: 42, alignItems: "center", justifyContent: "center", marginTop: 4 },
  textButtonLabel: { color: "rgba(245,245,248,0.82)", fontSize: 8, fontWeight: "900", letterSpacing: 0.4 },
  loginWrap: { flex: 1, justifyContent: "center", paddingHorizontal: 20, paddingTop: 150, paddingBottom: 26 },
  loginCard: {
    width: "100%",
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(0,0,0,0.20)",
    padding: 14,
    gap: 10
  },
  loginInput: {
    minHeight: 50,
    borderRadius: 13,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.25)",
    backgroundColor: "rgba(0,0,0,0.22)",
    color: "#FFFFFF",
    paddingHorizontal: 14,
    fontSize: 14
  },
  loginButton: {
    minHeight: 50,
    borderRadius: 13,
    backgroundColor: "#FFFFFF",
    alignItems: "center",
    justifyContent: "center",
    flexDirection: "row",
    gap: 8
  },
  loginButtonText: { color: "#050505", fontSize: 11, fontWeight: "900", letterSpacing: 0.6 },
  loginSpinner: { marginRight: 2 },
  onboardingScroll: { padding: 16, paddingBottom: 34 },
  warningCard: {
    borderRadius: 15,
    borderWidth: 1,
    borderColor: "rgba(222,72,80,0.38)",
    backgroundColor: "rgba(89,13,18,0.32)",
    padding: 14,
    marginBottom: 8
  },
  warningTitle: { color: "#FF9A9F", fontSize: 13, fontWeight: "900", marginBottom: 5 },
  termSection: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.28)",
    padding: 13,
    marginTop: 7
  },
  termTitle: { color: "#FFFFFF", fontSize: 13, fontWeight: "900", marginBottom: 5 },
  termEmphasis: { color: "#FFFFFF", fontSize: 11, lineHeight: 17, fontWeight: "800", marginTop: 7 },
  checkRow: {
    flexDirection: "row",
    gap: 10,
    alignItems: "flex-start",
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(5,5,7,0.30)",
    padding: 13,
    marginTop: 12
  },
  checkIcon: { color: "#FFFFFF", fontSize: 21, lineHeight: 23 },
  checkText: { flex: 1, color: "#F0F0F4", fontSize: 11, lineHeight: 17, fontWeight: "700" },
  nameScroll: { flexGrow: 1, justifyContent: "center", padding: 18 },
  input: {
    minHeight: 50,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(0,0,0,0.24)",
    color: "#FFFFFF",
    paddingHorizontal: 13,
    fontSize: 14,
    marginTop: 11
  },
  counter: { color: "rgba(235,235,240,0.58)", fontSize: 8, textAlign: "right", marginTop: 4 },
  primaryButton: {
    minHeight: 50,
    borderRadius: 12,
    backgroundColor: "#FFFFFF",
    alignItems: "center",
    justifyContent: "center",
    flexDirection: "row",
    gap: 8,
    paddingHorizontal: 16,
    marginTop: 13
  },
  primaryButtonText: { color: "#050505", fontSize: 11, fontWeight: "900", letterSpacing: 0.5 },
  primarySpinner: { marginRight: 2 },
  disabled: { opacity: 0.42 },
  appShell: { flex: 1 },
  appScroll: { flex: 1, backgroundColor: "transparent" },
  appContent: { paddingHorizontal: 12, paddingTop: 10, paddingBottom: 20 },
  chatHeader: { minHeight: 48, flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 10 },
  chatBack: {
    width: 42,
    height: 42,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(5,5,7,0.24)",
    alignItems: "center",
    justifyContent: "center"
  },
  chatBackText: { color: "#FFFFFF", fontSize: 29, lineHeight: 31, marginTop: -3 },
  chatTitle: { color: "#FFFFFF", fontSize: 18, fontWeight: "900" },
  chatHeaderSpacer: { flex: 1 },
  profileMiniButton: {
    width: 42,
    height: 42,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(5,5,7,0.24)",
    alignItems: "center",
    justifyContent: "center"
  },
  profileMiniHead: { width: 8, height: 8, borderRadius: 4, borderWidth: 1.4, borderColor: "#FFFFFF", position: "absolute", top: 10 },
  profileMiniShoulders: { width: 18, height: 9, borderTopLeftRadius: 9, borderTopRightRadius: 9, borderWidth: 1.4, borderBottomWidth: 0, borderColor: "#FFFFFF", position: "absolute", bottom: 8 },
  bottomNav: {
    flexShrink: 0,
    minHeight: 68,
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "rgba(3,3,5,0.62)",
    borderTopWidth: 1,
    borderTopColor: "rgba(255,255,255,0.14)",
    paddingHorizontal: 4,
    paddingTop: 3
  },
  navItem: { flex: 1, alignItems: "center", justifyContent: "center", minHeight: 61, gap: 3 },
  navGlyphBox: { width: 27, height: 25, alignItems: "center", justifyContent: "center", position: "relative" },
  homeRoof: { position: "absolute", width: 14, height: 14, top: 2, transform: [{ rotate: "45deg" }], borderLeftWidth: 1.8, borderTopWidth: 1.8, borderRadius: 2, backgroundColor: "transparent" },
  homeBody: { position: "absolute", width: 18, height: 14, bottom: 2, borderWidth: 1.8, borderTopWidth: 0, borderBottomLeftRadius: 3, borderBottomRightRadius: 3, backgroundColor: "transparent" },
  folderBody: { width: 22, height: 16, marginTop: 4, borderWidth: 1.8, borderRadius: 3, position: "relative", backgroundColor: "transparent" },
  folderTab: { position: "absolute", left: 2, top: -6, width: 9, height: 6, borderWidth: 1.8, borderBottomWidth: 0, borderTopLeftRadius: 3, borderTopRightRadius: 3, backgroundColor: "transparent" },
  socialSquare: { width: 15, height: 15, borderRadius: 2, borderWidth: 1.8 },
  keyRing: { position: "absolute", left: 2, top: 4, width: 10, height: 10, borderRadius: 5, borderWidth: 1.8 },
  keyShaft: { position: "absolute", width: 14, height: 2, left: 10, top: 12, borderRadius: 1, transform: [{ rotate: "-42deg" }] },
  keyToothA: { position: "absolute", width: 2, height: 5, right: 5, bottom: 5, borderRadius: 1, transform: [{ rotate: "48deg" }] },
  keyToothB: { position: "absolute", width: 2, height: 4, right: 2, bottom: 7, borderRadius: 1, transform: [{ rotate: "48deg" }] },
  settingsRing: { width: 18, height: 18, borderRadius: 9, borderWidth: 1.7, alignItems: "center", justifyContent: "center" },
  settingsCore: { width: 6, height: 6, borderRadius: 3, borderWidth: 1.5 },
  settingsSpokeTop: { position: "absolute", width: 2, height: 4, top: 1, borderRadius: 1 },
  settingsSpokeBottom: { position: "absolute", width: 2, height: 4, bottom: 1, borderRadius: 1 },
  settingsSpokeLeft: { position: "absolute", width: 4, height: 2, left: 1, borderRadius: 1 },
  settingsSpokeRight: { position: "absolute", width: 4, height: 2, right: 1, borderRadius: 1 },
  navText: { color: "rgba(225,225,232,0.56)", fontSize: 7, fontWeight: "800" },
  navTextActive: { color: "#FFFFFF", fontWeight: "900" }
});
