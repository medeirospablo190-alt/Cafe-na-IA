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

function formatExpiry(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

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

export default function AppRoot() {
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

    return () => { active = false; };
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
        "Nas próximas aberturas, o GRUPO LUA pedirá a proteção do próprio celular antes de liberar a sessão salva. Sua senha/chave de login não é armazenada para isso."
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
      // Se o armazenamento seguro local estiver indisponível, o login continua normal.
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
      setMessage(readableError(error));
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
      await clearLocalSession(
        "Sessão encerrada no servidor e removida deste aparelho. A autorização do dispositivo foi preservada."
      );
    } catch (error) {
      if (sessionIsDefinitelyInvalid(error)) {
        await clearLocalSession("A sessão já não era válida no servidor e foi removida deste aparelho.");
      } else {
        setMessage(
          `Não foi possível confirmar o encerramento no servidor: ${readableError(error)} A sessão foi mantida neste aparelho para você tentar novamente.`
        );
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
          message={message}
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
    if (appUnlocked && account && session && sessionToken && deviceToken) {
      return (
        <HomeShell
          account={account}
          session={session}
          sessionToken={sessionToken}
          deviceToken={deviceToken}
          tab={tab}
          onTab={setTab}
          onSignOut={signOutLocal}
        />
      );
    }
    return <BootScreen label="Confirmando acesso..." />;
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
    session,
    sessionToken,
    deviceToken,
    tab
  ]);

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <SafeAreaView style={styles.root} edges={["top", "bottom"]}>
        {body}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

function Brand() {
  return (
    <View style={styles.brandWrap}>
      <Text style={styles.brandMoon}>☾</Text>
      <Text style={styles.brand}>GRUPO LUA</Text>
      <Text style={styles.byline}>by CAFEÍNA</Text>
    </View>
  );
}

function BootScreen({ label = "Verificando sessão segura..." }: { label?: string }) {
  return (
    <View style={styles.center}>
      <Brand />
      <ActivityIndicator size="small" />
      <Text style={styles.mutedCenter}>{label}</Text>
    </View>
  );
}

function ConfigurationScreen() {
  return (
    <View style={styles.center}>
      <Brand />
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Servidor ainda não configurado</Text>
        <Text style={styles.paragraph}>
          Esta build ainda não recebeu o endereço da Control API. O aplicativo permanece bloqueado para evitar enviar credenciais ao endereço errado.
        </Text>
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
    <ImageBackground source={{ uri: LOGIN_BACKGROUND_DATA_URI }} style={styles.loginBackground} resizeMode="cover">
      <View style={styles.photoShade} />
      <View style={styles.unlockWrap}>
        <View style={styles.unlockCard}>
          <Text style={styles.eyebrowLight}>CONTA JÁ CADASTRADA</Text>
          <Text style={styles.unlockTitle}>Confirme no celular</Text>
          <Text style={styles.loginHelp}>
            Use a proteção do próprio aparelho para liberar a sessão salva. Sua chave de login não fica armazenada para este acesso.
          </Text>
          {message ? <Text style={styles.loginError}>{message}</Text> : null}
          <PrimaryButton title={busy ? "CONFIRMANDO..." : "LIBERAR COM O CELULAR"} onPress={onUnlock} disabled={busy} />
          <Pressable style={styles.textButton} onPress={onUseLogin} disabled={busy}>
            <Text style={styles.textButtonLabel}>USAR LOGIN NOVAMENTE</Text>
          </Pressable>
        </View>
      </View>
    </ImageBackground>
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
      <Brand />
      <View style={styles.card}>
        <Text style={styles.eyebrow}>SESSÃO PRESERVADA</Text>
        <Text style={styles.cardTitle}>Não conseguimos confirmar o servidor</Text>
        <Text style={styles.paragraph}>A sessão continua salva porque uma falha temporária de rede não deve apagar seu acesso local.</Text>
        {message ? <Text style={styles.error}>{message}</Text> : null}
        <PrimaryButton title={busy ? "CONFIRMANDO..." : "TENTAR NOVAMENTE"} onPress={onRetry} disabled={busy} />
        <Pressable style={styles.textButton} onPress={onDiscard} disabled={busy}>
          <Text style={styles.textButtonLabel}>DESCARTAR SESSÃO E USAR LOGIN</Text>
        </Pressable>
      </View>
    </View>
  );
}

function LoginScreen({
  login,
  credential,
  busy,
  message,
  onLogin,
  onCredential,
  onSubmit
}: {
  login: string;
  credential: string;
  busy: boolean;
  message: string | null;
  onLogin: (value: string) => void;
  onCredential: (value: string) => void;
  onSubmit: () => void;
}) {
  return (
    <ImageBackground source={{ uri: LOGIN_BACKGROUND_DATA_URI }} style={styles.loginBackground} resizeMode="cover">
      <View style={styles.photoShade} />
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={styles.loginScroll} keyboardShouldPersistTaps="handled">
          <View style={styles.loginCard}>
            <Text style={styles.eyebrowLight}>ACESSO PRIVADO</Text>
            <Text style={styles.loginTitle}>Entrar</Text>
            <Text style={styles.loginHelp}>Entre uma vez. Depois do login, você pode ativar o acesso rápido pelo próprio celular; a opção também fica disponível em Configurações.</Text>
            <TextInput
              value={login}
              onChangeText={onLogin}
              placeholder="Login"
              placeholderTextColor="#B4B4BA"
              style={styles.loginInput}
              autoCapitalize="none"
              autoCorrect={false}
              textContentType="username"
            />
            <TextInput
              value={credential}
              onChangeText={onCredential}
              placeholder="Chave de acesso"
              placeholderTextColor="#B4B4BA"
              style={styles.loginInput}
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
              textContentType="password"
            />
            {message ? <Text style={styles.loginError}>{message}</Text> : null}
            <PrimaryButton
              title={busy ? "VALIDANDO..." : "ENTRAR"}
              onPress={onSubmit}
              disabled={busy || !login.trim() || !credential}
            />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </ImageBackground>
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
    <View style={styles.flex}>
      <ScrollView contentContainerStyle={styles.onboardingScroll}>
        <Brand />
        <View style={styles.warningCard}>
          <Text style={styles.warningEyebrow}>LEIA COM ATENÇÃO</Text>
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
        <PrimaryButton title={busy ? "CONFIRMANDO..." : "CONTINUAR"} onPress={onContinue} disabled={!checked || busy} />
      </ScrollView>
    </View>
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
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={styles.nameScroll} keyboardShouldPersistTaps="handled">
        <Brand />
        <View style={styles.card}>
          <Text style={styles.eyebrow}>IDENTIDADE PÚBLICA</Text>
          <Text style={styles.loginTitle}>Escolha seu nome</Text>
          <Text style={styles.paragraph}>Use um pseudônimo de 3 a 30 caracteres. Não use login, chave ou informações pessoais.</Text>
          <TextInput
            value={value}
            onChangeText={onChange}
            placeholder="Seu pseudônimo..."
            placeholderTextColor="#67676E"
            style={styles.input}
            autoCapitalize="words"
            autoCorrect={false}
            maxLength={30}
          />
          <Text style={styles.counter}>{length}/30</Text>
          {message ? <Text style={styles.error}>{message}</Text> : null}
          <PrimaryButton title={busy ? "VERIFICANDO..." : "CONFIRMAR NOME"} onPress={onSubmit} disabled={busy || length < 3 || length > 30} />
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function HomeShell({
  account,
  session,
  sessionToken,
  deviceToken,
  tab,
  onTab,
  onSignOut
}: {
  account: PublicAccount;
  session: App1Session;
  sessionToken: string;
  deviceToken: string;
  tab: Tab;
  onTab: (tab: Tab) => void;
  onSignOut: () => void;
}) {
  const [socialSection, setSocialSection] = useState<SocialSection>("feed");
  const isDev = account.role === "DEV";
  const pageLabel: Record<Tab, string> = {
    home: "Início",
    files: "Arquivos",
    social: "Social",
    keys: "Chaves",
    settings: "Configurações"
  };

  return (
    <View style={styles.appShell}>
      <Pressable
        style={styles.appHeader}
        onPress={() => onTab("settings")}
        accessibilityRole="button"
        accessibilityLabel="Abrir perfil e configurações"
      >
        <View style={[styles.avatar, isDev && styles.avatarDev]}>
          <Text style={styles.avatarText}>{(account.publicName || "L").slice(0, 1).toUpperCase()}</Text>
        </View>
        <View style={styles.headerIdentity}>
          <View style={styles.identityRow}>
            <Text style={styles.publicName}>{account.publicName || "Perfil"}</Text>
            {isDev ? <Text style={styles.devBadge}>DEV</Text> : null}
          </View>
          <Text style={styles.sessionLine}>Sessão até {formatExpiry(session.expiresAt)}</Text>
        </View>
      </Pressable>

      <ScrollView
        style={styles.appScroll}
        contentContainerStyle={styles.appContent}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        <Text style={styles.eyebrow}>GRUPO LUA</Text>
        <Text style={styles.pageTitle}>{pageLabel[tab]}</Text>

        {tab === "home" ? (
          <>
            <View style={[styles.hero, isDev && styles.heroDev]}>
              <Text style={styles.heroKicker}>ACESSO LIBERADO</Text>
              <Text style={styles.heroTitle}>Conta pronta neste aparelho</Text>
              <Text style={styles.paragraph}>Acesso principal, arquivos, Social, chaves e configurações em uma navegação compacta pensada para celular.</Text>
            </View>
            <View style={styles.grid}>
              <Feature title="Social + Chat" text="Feed e conversas no mesmo espaço, sem ocupar outro botão na barra principal." />
              <Feature title="Chaves" text="FREE/VIP e vínculo de aparelho controlados pelo servidor." />
              <Feature title="Arquivos" text="Códigos, loadstrings e cofre de mídia local." />
              <Feature title="Configurações" text="Perfil, privacidade, acesso rápido e saída da conta." />
            </View>
          </>
        ) : tab === "files" ? (
          <FilesScreen sessionToken={sessionToken} deviceToken={deviceToken} profileId={account.profileId} />
        ) : tab === "social" ? (
          <>
            <View style={styles.segment}>
              <Pressable style={[styles.segmentItem, socialSection === "feed" && styles.segmentActive]} onPress={() => setSocialSection("feed")}>
                <Text style={[styles.segmentText, socialSection === "feed" && styles.segmentTextActive]}>FEED</Text>
              </Pressable>
              <Pressable style={[styles.segmentItem, socialSection === "chat" && styles.segmentActive]} onPress={() => setSocialSection("chat")}>
                <Text style={[styles.segmentText, socialSection === "chat" && styles.segmentTextActive]}>CHAT</Text>
              </Pressable>
            </View>
            {socialSection === "feed" ? (
              <SocialFeedScreen sessionToken={sessionToken} deviceToken={deviceToken} viewerRole={account.role} />
            ) : (
              <ChatsScreen sessionToken={sessionToken} deviceToken={deviceToken} />
            )}
          </>
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
        <NavItem label="Início" active={tab === "home"} onPress={() => onTab("home")} />
        <NavItem label="Arquivos" active={tab === "files"} onPress={() => onTab("files")} />
        <NavItem label="Social" active={tab === "social"} onPress={() => onTab("social")} />
        <NavItem label="Chaves" active={tab === "keys"} onPress={() => onTab("keys")} />
        <NavItem label="Config." active={tab === "settings"} onPress={() => onTab("settings")} />
      </View>
    </View>
  );
}

function Feature({ title, text }: { title: string; text: string }) {
  return (
    <View style={styles.feature}>
      <Text style={styles.featureTitle}>{title}</Text>
      <Text style={styles.featureText}>{text}</Text>
    </View>
  );
}

function NavItem({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable style={styles.navItem} onPress={onPress}>
      <View style={[styles.navDot, active && styles.navDotActive]} />
      <Text style={[styles.navText, active && styles.navTextActive]}>{label}</Text>
    </Pressable>
  );
}

function PrimaryButton({ title, onPress, disabled }: { title: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable style={[styles.primaryButton, disabled && styles.disabled]} onPress={onPress} disabled={disabled}>
      <Text style={styles.primaryButtonText}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#030303" },
  flex: { flex: 1 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 18, gap: 12 },
  mutedCenter: { color: "#88888F", fontSize: 12, textAlign: "center" },
  brandWrap: { alignItems: "center", marginBottom: 16 },
  brandMoon: { color: "#D53037", fontSize: 30, marginBottom: -3 },
  brand: { color: "#FFFFFF", fontSize: 24, fontWeight: "900", letterSpacing: 3.4 },
  byline: { color: "#707077", fontSize: 9, fontWeight: "800", letterSpacing: 1.5, marginTop: 5 },
  loginBackground: { flex: 1, width: "100%", backgroundColor: "#020202" },
  photoShade: { position: "absolute", top: 0, right: 0, bottom: 0, left: 0, backgroundColor: "rgba(0,0,0,0.10)" },
  loginScroll: { flexGrow: 1, justifyContent: "center", paddingHorizontal: 18, paddingTop: 170, paddingBottom: 22 },
  loginCard: { borderRadius: 18, padding: 16, backgroundColor: "rgba(4,4,5,0.34)", borderWidth: 1, borderColor: "rgba(210,49,57,0.34)" },
  eyebrowLight: { color: "#D8D8DD", fontSize: 9, fontWeight: "900", letterSpacing: 1.6 },
  loginTitle: { color: "#FFFFFF", fontSize: 25, fontWeight: "900", marginTop: 5, marginBottom: 3 },
  loginHelp: { color: "#D0D0D5", fontSize: 11, lineHeight: 16, textShadowColor: "rgba(0,0,0,0.9)", textShadowRadius: 3 },
  loginInput: { minHeight: 49, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.24)", backgroundColor: "rgba(3,3,4,0.40)", color: "#FFFFFF", paddingHorizontal: 13, fontSize: 14, marginTop: 10 },
  loginError: { color: "#FF8186", fontSize: 11, lineHeight: 16, marginTop: 10, textShadowColor: "#000", textShadowRadius: 2 },
  unlockWrap: { flex: 1, justifyContent: "center", paddingHorizontal: 18, paddingTop: 170, paddingBottom: 22 },
  unlockCard: { borderRadius: 18, padding: 16, backgroundColor: "rgba(4,4,5,0.34)", borderWidth: 1, borderColor: "rgba(210,49,57,0.34)" },
  unlockTitle: { color: "#FFFFFF", fontSize: 23, fontWeight: "900", marginTop: 5, marginBottom: 4 },
  onboardingScroll: { padding: 16, paddingBottom: 34 },
  nameScroll: { flexGrow: 1, justifyContent: "center", padding: 18 },
  card: { width: "100%", maxWidth: 520, borderRadius: 16, borderWidth: 1, borderColor: "#303036", backgroundColor: "#09090BCF", padding: 16 },
  cardTitle: { color: "#FFFFFF", fontSize: 18, fontWeight: "900", marginTop: 5, marginBottom: 6 },
  warningCard: { borderRadius: 14, padding: 14, backgroundColor: "#130708B8", borderWidth: 1, borderColor: "#542126", marginBottom: 8 },
  warningEyebrow: { color: "#FF6B72", fontSize: 11, fontWeight: "900", letterSpacing: 0.7, marginBottom: 5 },
  eyebrow: { color: "#85858C", fontSize: 9, fontWeight: "900", letterSpacing: 1.5 },
  paragraph: { color: "#A1A1A8", fontSize: 12, lineHeight: 18 },
  input: { minHeight: 50, borderRadius: 12, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#101013C7", color: "#FFFFFF", paddingHorizontal: 13, fontSize: 14, marginTop: 11 },
  counter: { color: "#707078", fontSize: 8, textAlign: "right", marginTop: 4 },
  error: { color: "#FF696F", fontSize: 11, lineHeight: 17, marginTop: 10 },
  primaryButton: { minHeight: 50, borderRadius: 12, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 16, marginTop: 13 },
  primaryButtonText: { color: "#050505", fontSize: 11, fontWeight: "900", letterSpacing: 0.5 },
  disabled: { opacity: 0.42 },
  textButton: { minHeight: 42, alignItems: "center", justifyContent: "center", marginTop: 4 },
  textButtonLabel: { color: "#C6C6CC", fontSize: 8, fontWeight: "900", letterSpacing: 0.4 },
  termSection: { borderRadius: 13, borderWidth: 1, borderColor: "#25252A", backgroundColor: "#08080AB8", padding: 13, marginTop: 7 },
  termTitle: { color: "#FFFFFF", fontSize: 13, fontWeight: "900", marginBottom: 5 },
  termEmphasis: { color: "#E7E7EB", fontSize: 11, lineHeight: 17, fontWeight: "800", marginTop: 7 },
  checkRow: { flexDirection: "row", gap: 10, alignItems: "flex-start", borderRadius: 13, borderWidth: 1, borderColor: "#34343A", backgroundColor: "#0B0B0DB8", padding: 13, marginTop: 12 },
  checkIcon: { color: "#FFFFFF", fontSize: 21, lineHeight: 23 },
  checkText: { flex: 1, color: "#D3D3D8", fontSize: 11, lineHeight: 17, fontWeight: "700" },
  appShell: { flex: 1 },
  appHeader: { minHeight: 60, flexDirection: "row", alignItems: "center", paddingHorizontal: 14, borderBottomWidth: 1, borderBottomColor: "#1E1E22", gap: 9 },
  avatar: { width: 38, height: 38, borderRadius: 19, backgroundColor: "#17171BC7", borderWidth: 1, borderColor: "#48484F", alignItems: "center", justifyContent: "center" },
  avatarDev: { borderColor: "#D93A41", borderWidth: 2 },
  avatarText: { color: "#FFFFFF", fontSize: 14, fontWeight: "900" },
  headerIdentity: { flex: 1 },
  identityRow: { flexDirection: "row", alignItems: "center", gap: 6 },
  publicName: { color: "#FFFFFF", fontSize: 13, fontWeight: "900" },
  devBadge: { color: "#FF686F", backgroundColor: "#21090BD9", borderRadius: 6, paddingHorizontal: 6, paddingVertical: 2, fontSize: 8, fontWeight: "900" },
  sessionLine: { color: "#74747B", fontSize: 8, marginTop: 3 },
  appScroll: { flex: 1 },
  appContent: { padding: 14, paddingBottom: 20 },
  pageTitle: { color: "#FFFFFF", fontSize: 25, fontWeight: "900", marginTop: 3, marginBottom: 10 },
  hero: { borderRadius: 16, borderWidth: 1, borderColor: "#303037", backgroundColor: "#0B0B0EB8", padding: 15 },
  heroDev: { borderColor: "#4A1B20", backgroundColor: "#100708A8" },
  heroKicker: { color: "#70DF88", fontSize: 8, fontWeight: "900", letterSpacing: 1.2 },
  heroTitle: { color: "#FFFFFF", fontSize: 18, fontWeight: "900", marginTop: 6, marginBottom: 5 },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 8, marginTop: 9 },
  feature: { width: "48%", flexGrow: 1, minHeight: 94, borderRadius: 14, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#09090BA8", padding: 12 },
  featureTitle: { color: "#FFFFFF", fontSize: 12, fontWeight: "900" },
  featureText: { color: "#87878E", fontSize: 10, lineHeight: 15, marginTop: 5 },
  segment: { flexDirection: "row", borderRadius: 12, borderWidth: 1, borderColor: "#333339", backgroundColor: "#09090BA8", padding: 3, marginBottom: 10 },
  segmentItem: { flex: 1, minHeight: 38, alignItems: "center", justifyContent: "center", borderRadius: 9 },
  segmentActive: { backgroundColor: "#FFFFFF" },
  segmentText: { color: "#8A8A92", fontSize: 9, fontWeight: "900" },
  segmentTextActive: { color: "#070708" },
  bottomNav: { flexShrink: 0, minHeight: 60, flexDirection: "row", alignItems: "center", backgroundColor: "#070709F0", borderTopWidth: 1, borderTopColor: "#252529", paddingHorizontal: 4 },
  navItem: { flex: 1, alignItems: "center", justifyContent: "center", minHeight: 54, gap: 4 },
  navDot: { width: 5, height: 5, borderRadius: 3, backgroundColor: "transparent" },
  navDotActive: { backgroundColor: "#D63A41" },
  navText: { color: "#74747B", fontSize: 8, fontWeight: "800" },
  navTextActive: { color: "#FFFFFF" }
});
