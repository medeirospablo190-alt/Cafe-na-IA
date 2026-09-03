import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
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

const SESSION_KEY = "grupo-lua-app1-session-v1";
const DEVICE_TOKEN_KEY = "grupo-lua-app1-device-token-v1";

type Tab = "home" | "files" | "social" | "keys" | "chats";

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
    text: "Notificações de curtidas, comentários, favoritos e mensagens são temporárias e são removidas após 24 horas. A remoção da notificação não significa necessariamente que o conteúdo relacionado também foi apagado."
  },
  {
    title: "Chaves, menus e outros dados",
    text: "A regra de 24 horas é aplicada à área Social e às mensagens. Chaves de acesso, menus, scripts, configurações e outros dados administrativos não são apagados automaticamente após 24 horas."
  },
  {
    title: "Privacidade das conversas",
    text: "Enquanto sua conta estiver ativa, suas conversas privadas não ficam disponíveis para visualização administrativa comum. Em situações de denúncia ou violação das regras, a conta poderá ser suspensa para que somente o conteúdo necessário seja analisado."
  },
  {
    title: "Proteja seu acesso",
    text: "Não compartilhe o aplicativo, seu login, sua chave de acesso, sua sessão ou qualquer outra informação utilizada para entrar na sua conta. Após 3 tentativas de login incorretas, sua conta poderá ser bloqueada automaticamente por segurança."
  },
  {
    title: "Outro celular ou dispositivo",
    text: "Sua conta é vinculada aos dispositivos autorizados. Se precisar trocar ou adicionar outro celular, peça autorização a um DEV do GRUPO LUA antes de tentar fazer login no novo aparelho. Tentativas em dispositivo não autorizado podem ser recusadas e, após 3 tentativas de segurança, a conta poderá ser bloqueada."
  },
  {
    title: "Identidade e privacidade pessoal",
    text: "Use apenas pseudônimos no aplicativo. Não publique fotos pessoais suas ou de outras pessoas e não compartilhe informações reais que possam identificar você ou terceiros, como nome completo, endereço, telefone, documentos, escola, local de trabalho, localização ou redes sociais pessoais.",
    emphasis: "Não utilize seu nome real, login, chave de acesso ou outras informações de autenticação como nome público."
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

export default function App() {
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

  const onboarding = account?.onboarding;
  const authenticated = Boolean(sessionToken && deviceToken && account);
  const appUnlocked = Boolean(authenticated && onboarding?.completed && session?.kind === "FULL");

  useEffect(() => {
    let active = true;
    Promise.all([
      SecureStore.getItemAsync(SESSION_KEY),
      SecureStore.getItemAsync(DEVICE_TOKEN_KEY)
    ])
      .then(async ([savedSession, savedDevice]) => {
        if (!active) return;
        setSessionToken(savedSession);
        setDeviceToken(savedDevice);
        if (savedSession && savedDevice) {
          await restoreSession(savedSession, savedDevice, active);
        }
      })
      .catch(() => {
        if (active) setMessage("Não foi possível restaurar a sessão segura deste aparelho.");
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
      setMessage(null);
      return true;
    } catch (error) {
      await SecureStore.deleteItemAsync(SESSION_KEY).catch(() => {});
      if (active) {
        setSessionToken(null);
        setSession(null);
        setAccount(null);
        setMessage(readableError(error));
      }
      return false;
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

      setLogin("");
      setCredential("");
      setTermsChecked(false);
      setPublicName("");
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
      setPublicName("");
      setTab("home");
    } catch (error) {
      setMessage(readableError(error));
    } finally {
      setBusy(false);
    }
  }

  async function signOutLocal() {
    await SecureStore.deleteItemAsync(SESSION_KEY).catch(() => {});
    setSessionToken(null);
    setSession(null);
    setAccount(null);
    setLogin("");
    setCredential("");
    setTermsChecked(false);
    setPublicName("");
    setTab("home");
    setMessage("Sessão encerrada neste aparelho. A autorização do dispositivo foi preservada.");
  }

  const body = useMemo(() => {
    if (booting) return <BootScreen />;
    if (!API_URL) return <ConfigurationScreen />;
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
    if (appUnlocked && account && session) {
      return (
        <HomeShell
          account={account}
          session={session}
          tab={tab}
          onTab={setTab}
          onSignOut={signOutLocal}
        />
      );
    }
    return <BootScreen label="Confirmando acesso de 24 horas..." />;
  }, [
    booting,
    authenticated,
    onboarding?.termsAccepted,
    onboarding?.publicNameVerified,
    onboarding?.completed,
    appUnlocked,
    login,
    credential,
    busy,
    message,
    termsChecked,
    publicName,
    account,
    session,
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
          Esta build do App 1 ainda não recebeu o endereço privado da Control API. O aplicativo permanece bloqueado para evitar enviar credenciais ao endereço errado.
        </Text>
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
    <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={styles.loginScroll} keyboardShouldPersistTaps="handled">
        <Brand />
        <View style={styles.loginCard}>
          <Text style={styles.eyebrow}>ACESSO PRIVADO</Text>
          <Text style={styles.loginTitle}>Entrar</Text>
          <Text style={styles.paragraph}>
            Use o login e a chave de acesso entregues pelo GRUPO LUA. Depois da autenticação, essas informações deixam a interface e o aplicativo passa a usar somente a sessão segura.
          </Text>

          <TextInput
            value={login}
            onChangeText={onLogin}
            placeholder="Login"
            placeholderTextColor="#5D5D63"
            style={styles.input}
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="username"
          />
          <TextInput
            value={credential}
            onChangeText={onCredential}
            placeholder="Chave de acesso"
            placeholderTextColor="#5D5D63"
            style={styles.input}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            textContentType="password"
          />

          {message ? <Text style={styles.error}>{message}</Text> : null}

          <PrimaryButton
            title={busy ? "VALIDANDO..." : "ENTRAR"}
            onPress={onSubmit}
            disabled={busy || !login.trim() || !credential}
          />

          <Text style={styles.privacyNote}>
            O aplicativo não usa seu login como nome público.
          </Text>
        </View>
      </ScrollView>
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
    <View style={styles.flex}>
      <ScrollView contentContainerStyle={styles.onboardingScroll}>
        <Brand />
        <View style={styles.warningCard}>
          <Text style={styles.warningEyebrow}>⚠ LEIA COM ATENÇÃO ANTES DE CONTINUAR</Text>
          <Text style={styles.termsIntro}>
            Este aviso contém informações importantes sobre o funcionamento do aplicativo, sua privacidade, seus dados e as regras de acesso à sua conta. Leia todo o conteúdo antes de confirmar.
          </Text>
        </View>

        {NOTICE_SECTIONS.map((section) => (
          <View key={section.title} style={styles.termSection}>
            <Text style={styles.termTitle}>{section.title}</Text>
            <Text style={styles.paragraph}>{section.text}</Text>
            {section.emphasis ? <Text style={styles.termEmphasis}>{section.emphasis}</Text> : null}
          </View>
        ))}

        <View style={styles.termSection}>
          <Text style={styles.termTitle}>Nome público</Text>
          <Text style={styles.paragraph}>
            No primeiro acesso você deverá escolher um pseudônimo para ser utilizado no aplicativo e no Social. Esse nome será exibido no perfil, posts, comentários, curtidas e favoritos.
          </Text>
          <Text style={styles.termEmphasis}>
            Use apenas um pseudônimo. Não use seu nome real, login, chave de acesso ou informações pessoais.
          </Text>
        </View>

        <Pressable style={styles.checkRow} onPress={onToggle} accessibilityRole="checkbox" accessibilityState={{ checked }}>
          <Text style={styles.checkIcon}>{checked ? "☑" : "☐"}</Text>
          <Text style={styles.checkText}>
            Li com atenção e aceito os Termos de Uso, as regras de privacidade e as regras de segurança do GRUPO LUA.
          </Text>
        </Pressable>

        {message ? <Text style={styles.error}>{message}</Text> : null}

        <PrimaryButton
          title={busy ? "CONFIRMANDO..." : "CONTINUAR"}
          onPress={onContinue}
          disabled={!checked || busy}
        />
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
        <View style={styles.loginCard}>
          <Text style={styles.eyebrow}>IDENTIDADE PÚBLICA</Text>
          <Text style={styles.loginTitle}>Escolha seu nome</Text>
          <Text style={styles.paragraph}>
            Esse será o nome exibido no seu perfil e nas áreas sociais do aplicativo. O servidor verifica o pseudônimo antes de liberar o acesso.
          </Text>

          <TextInput
            value={value}
            onChangeText={onChange}
            placeholder="Digite seu pseudônimo..."
            placeholderTextColor="#5D5D63"
            style={styles.input}
            autoCapitalize="words"
            autoCorrect={false}
            maxLength={30}
          />
          <View style={styles.nameMetaRow}>
            <Text style={styles.nameRules}>
              3–30 caracteres • pseudônimo • sem nome real • sem login/chave • sem informações pessoais
            </Text>
            <Text style={styles.counter}>{length}/30</Text>
          </View>

          {message ? <Text style={styles.error}>{message}</Text> : null}

          <PrimaryButton
            title={busy ? "VERIFICANDO..." : "CONFIRMAR NOME"}
            onPress={onSubmit}
            disabled={busy || length < 3 || length > 30}
          />
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

function HomeShell({
  account,
  session,
  tab,
  onTab,
  onSignOut
}: {
  account: PublicAccount;
  session: App1Session;
  tab: Tab;
  onTab: (tab: Tab) => void;
  onSignOut: () => void;
}) {
  const isDev = account.role === "DEV";
  const pageLabel: Record<Tab, string> = {
    home: "Início",
    files: "Arquivos",
    social: "Social",
    keys: "Chaves",
    chats: "Chats"
  };

  return (
    <View style={styles.appShell}>
      <View style={styles.appHeader}>
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
        <Pressable onPress={onSignOut} style={styles.signOutButton}>
          <Text style={styles.signOutText}>SAIR</Text>
        </Pressable>
      </View>

      <ScrollView contentContainerStyle={styles.appContent}>
        <Text style={styles.eyebrow}>GRUPO LUA</Text>
        <Text style={styles.pageTitle}>{pageLabel[tab]}</Text>

        {tab === "home" ? (
          <>
            <View style={[styles.hero, isDev && styles.heroDev]}>
              <Text style={styles.heroKicker}>ACESSO LIBERADO</Text>
              <Text style={styles.heroTitle}>Sessão de 24 horas ativa</Text>
              <Text style={styles.paragraph}>
                Seu primeiro acesso foi concluído. Termos e pseudônimo foram confirmados pelo servidor e o aplicativo pode ser reaberto sem novo login enquanto esta sessão permanecer válida.
              </Text>
            </View>
            <View style={styles.grid}>
              <Feature title="Social" text="Feed, perfis, comentários, curtidas e favoritos." />
              <Feature title="Chaves" text="Menus e chaves da sua conta." />
              <Feature title="Chats" text="Conversas privadas e temporárias." />
              <Feature title="Arquivos" text="Área de arquivos do aplicativo." />
            </View>
          </>
        ) : (
          <View style={styles.comingCard}>
            <Text style={styles.cardTitle}>{pageLabel[tab]}</Text>
            <Text style={styles.paragraph}>
              A estrutura desta área já está reservada no App 1. O módulo funcional será conectado nas próximas fases sem alterar o fluxo de autenticação e onboarding que já está pronto.
            </Text>
          </View>
        )}
      </ScrollView>

      <View style={styles.bottomNav}>
        <NavItem label="Início" active={tab === "home"} onPress={() => onTab("home")} />
        <NavItem label="Arquivos" active={tab === "files"} onPress={() => onTab("files")} />
        <NavItem label="Social" active={tab === "social"} onPress={() => onTab("social")} />
        <NavItem label="Chaves" active={tab === "keys"} onPress={() => onTab("keys")} />
        <NavItem label="Chats" active={tab === "chats"} onPress={() => onTab("chats")} />
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

function PrimaryButton({
  title,
  onPress,
  disabled
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
}) {
  return (
    <Pressable style={[styles.primaryButton, disabled && styles.disabled]} onPress={onPress} disabled={disabled}>
      <Text style={styles.primaryButtonText}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#030303" },
  flex: { flex: 1 },
  center: { flex: 1, alignItems: "center", justifyContent: "center", padding: 20, gap: 14 },
  mutedCenter: { color: "#7E7E84", fontSize: 12, textAlign: "center" },
  brandWrap: { alignItems: "center", marginBottom: 22 },
  brandMoon: { color: "#E33B42", fontSize: 34, marginBottom: -3 },
  brand: { color: "#FFFFFF", fontSize: 27, fontWeight: "900", letterSpacing: 4 },
  byline: { color: "#65656B", fontSize: 10, fontWeight: "800", letterSpacing: 1.8, marginTop: 6 },
  loginScroll: { flexGrow: 1, justifyContent: "center", padding: 18 },
  onboardingScroll: { padding: 18, paddingBottom: 36 },
  nameScroll: { flexGrow: 1, justifyContent: "center", padding: 18 },
  loginCard: { borderRadius: 22, padding: 20, backgroundColor: "#09090B", borderWidth: 1, borderColor: "#27272C" },
  warningCard: { borderRadius: 18, padding: 18, backgroundColor: "#130708", borderWidth: 1, borderColor: "#542126", marginBottom: 12 },
  warningEyebrow: { color: "#FF5A61", fontSize: 13, fontWeight: "900", letterSpacing: 0.7, lineHeight: 20 },
  termsIntro: { color: "#D0D0D5", fontSize: 13, lineHeight: 20, marginTop: 10 },
  eyebrow: { color: "#77777E", fontSize: 9, fontWeight: "900", letterSpacing: 1.8 },
  loginTitle: { color: "#FFFFFF", fontSize: 30, fontWeight: "900", marginTop: 7, marginBottom: 5 },
  paragraph: { color: "#98989F", fontSize: 13, lineHeight: 20 },
  input: { minHeight: 54, borderRadius: 14, borderWidth: 1, borderColor: "#2B2B30", backgroundColor: "#101013", color: "#FFFFFF", paddingHorizontal: 14, fontSize: 15, marginTop: 13 },
  error: { color: "#FF5A52", fontSize: 12, lineHeight: 18, marginTop: 12 },
  primaryButton: { minHeight: 52, borderRadius: 14, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 18, marginTop: 16 },
  primaryButtonText: { color: "#050505", fontSize: 12, fontWeight: "900", letterSpacing: 0.7 },
  disabled: { opacity: 0.38 },
  privacyNote: { color: "#66666D", fontSize: 10, lineHeight: 15, textAlign: "center", marginTop: 13 },
  termSection: { borderRadius: 16, borderWidth: 1, borderColor: "#202025", backgroundColor: "#08080A", padding: 16, marginTop: 9 },
  termTitle: { color: "#FFFFFF", fontSize: 14, fontWeight: "900", marginBottom: 7 },
  termEmphasis: { color: "#E7E7EB", fontSize: 12, lineHeight: 19, fontWeight: "800", marginTop: 9 },
  checkRow: { flexDirection: "row", gap: 11, alignItems: "flex-start", borderRadius: 16, borderWidth: 1, borderColor: "#313136", backgroundColor: "#0B0B0D", padding: 15, marginTop: 16 },
  checkIcon: { color: "#FFFFFF", fontSize: 23, lineHeight: 25 },
  checkText: { flex: 1, color: "#D3D3D8", fontSize: 12, lineHeight: 18, fontWeight: "700" },
  nameMetaRow: { flexDirection: "row", alignItems: "flex-start", gap: 12, marginTop: 8 },
  nameRules: { color: "#696970", fontSize: 9, lineHeight: 14, flex: 1 },
  counter: { color: "#696970", fontSize: 9, fontWeight: "800" },
  card: { width: "100%", maxWidth: 520, borderRadius: 18, borderWidth: 1, borderColor: "#29292E", backgroundColor: "#09090B", padding: 18 },
  cardTitle: { color: "#FFFFFF", fontSize: 16, fontWeight: "900", marginBottom: 7 },
  appShell: { flex: 1 },
  appHeader: { minHeight: 70, flexDirection: "row", alignItems: "center", paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: "#1B1B1F", gap: 11 },
  avatar: { width: 42, height: 42, borderRadius: 21, backgroundColor: "#17171B", borderWidth: 1, borderColor: "#424248", alignItems: "center", justifyContent: "center" },
  avatarDev: { borderColor: "#D93A41", borderWidth: 2 },
  avatarText: { color: "#FFFFFF", fontSize: 16, fontWeight: "900" },
  headerIdentity: { flex: 1 },
  identityRow: { flexDirection: "row", alignItems: "center", gap: 7 },
  publicName: { color: "#FFFFFF", fontSize: 14, fontWeight: "900" },
  devBadge: { color: "#FF5A61", backgroundColor: "#21090B", borderRadius: 6, paddingHorizontal: 6, paddingVertical: 2, fontSize: 8, fontWeight: "900" },
  sessionLine: { color: "#66666D", fontSize: 9, marginTop: 4 },
  signOutButton: { borderRadius: 9, borderWidth: 1, borderColor: "#303035", paddingHorizontal: 10, paddingVertical: 8 },
  signOutText: { color: "#A2A2A8", fontSize: 8, fontWeight: "900" },
  appContent: { padding: 18, paddingBottom: 100 },
  pageTitle: { color: "#FFFFFF", fontSize: 30, fontWeight: "900", marginTop: 5, marginBottom: 14 },
  hero: { borderRadius: 20, borderWidth: 1, borderColor: "#2A2A31", backgroundColor: "#0B0B0E", padding: 18 },
  heroDev: { borderColor: "#4A1B20", backgroundColor: "#100708" },
  heroKicker: { color: "#65D97F", fontSize: 9, fontWeight: "900", letterSpacing: 1.4 },
  heroTitle: { color: "#FFFFFF", fontSize: 21, fontWeight: "900", marginTop: 8, marginBottom: 7 },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 10, marginTop: 12 },
  feature: { width: "48%", flexGrow: 1, minHeight: 112, borderRadius: 16, borderWidth: 1, borderColor: "#232328", backgroundColor: "#09090B", padding: 14 },
  featureTitle: { color: "#FFFFFF", fontSize: 14, fontWeight: "900" },
  featureText: { color: "#77777E", fontSize: 11, lineHeight: 16, marginTop: 6 },
  comingCard: { borderRadius: 18, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#09090B", padding: 18 },
  bottomNav: { position: "absolute", left: 0, right: 0, bottom: 0, minHeight: 64, flexDirection: "row", alignItems: "center", backgroundColor: "#070709", borderTopWidth: 1, borderTopColor: "#202024", paddingHorizontal: 5 },
  navItem: { flex: 1, alignItems: "center", justifyContent: "center", minHeight: 58, gap: 5 },
  navDot: { width: 5, height: 5, borderRadius: 3, backgroundColor: "transparent" },
  navDotActive: { backgroundColor: "#FFFFFF" },
  navText: { color: "#66666D", fontSize: 9, fontWeight: "800" },
  navTextActive: { color: "#FFFFFF" }
});