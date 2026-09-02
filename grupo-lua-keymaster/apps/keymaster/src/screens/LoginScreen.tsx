import { useMemo, useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, SafeAreaView, Text, TextInput, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import * as Clipboard from "expo-clipboard";
import { KEYMASTER_MAX_CHARS } from "../config";
import { getDeviceIdentity } from "../device";
import { ApiError, loginKeymaster } from "../api";
import { Button } from "../components/Common";
import { styles } from "../styles";

export function LoginScreen({ onAuthenticated }: { onAuthenticated: (token: string) => Promise<void> }) {
  const [key, setKey] = useState("");
  const [show, setShow] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [lockedUntil, setLockedUntil] = useState<string | null>(null);

  const countLabel = useMemo(
    () => `${key.length.toLocaleString("pt-BR")} / ${KEYMASTER_MAX_CHARS.toLocaleString("pt-BR")}`,
    [key.length]
  );

  async function paste() {
    const value = await Clipboard.getStringAsync();
    setKey(value.slice(0, KEYMASTER_MAX_CHARS));
  }

  async function submit() {
    if (!key || loading) return;
    const keyForRequest = key;
    setLoading(true);
    setMessage("");
    try {
      const device = await getDeviceIdentity();
      const result = await loginKeymaster(keyForRequest, device);
      setKey("");
      await onAuthenticated(result.token);
    } catch (error) {
      setKey("");
      if (error instanceof ApiError) {
        if (error.code === "DEVICE_LOCKED") {
          const until = String(error.details?.lockedUntil || "");
          setLockedUntil(until || null);
          setMessage("Dispositivo bloqueado por 24 horas pelo servidor.");
        } else {
          const remaining = error.details?.attemptsRemaining;
          setMessage(`${error.message}${typeof remaining === "number" ? ` • Tentativas restantes: ${remaining}` : ""}`);
        }
      } else {
        setMessage("Não foi possível acessar o servidor.");
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <KeyboardAvoidingView style={styles.center} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <View style={styles.loginBrand}>
          <Text style={styles.brand}>Grupo Lua</Text>
          <Text style={styles.loginSubtitle}>KEYMASTER • acesso administrativo</Text>
        </View>

        <View style={styles.loginBox}>
          <View style={styles.labelRow}>
            <Text style={styles.label}>KEYMASTER ACCESS KEY</Text>
            <Text style={styles.counter}>{countLabel}</Text>
          </View>

          <TextInput
            value={key}
            onChangeText={setKey}
            maxLength={KEYMASTER_MAX_CHARS}
            secureTextEntry={!show}
            autoCapitalize="none"
            autoCorrect={false}
            spellCheck={false}
            textContentType="password"
            style={styles.input}
            placeholder="Cole a chave completa"
            placeholderTextColor="#666"
          />

          <View style={styles.rowGap}>
            <Pressable style={styles.halfButton} onPress={paste}><Text style={styles.halfButtonText}>COLAR</Text></Pressable>
            <Pressable style={styles.halfButton} onPress={() => setShow((v) => !v)}><Text style={styles.halfButtonText}>{show ? "OCULTAR" : "MOSTRAR"}</Text></Pressable>
          </View>

          {message ? <Text style={styles.error}>{message}</Text> : null}
          {lockedUntil ? <Text style={styles.small}>Bloqueado até: {new Date(lockedUntil).toLocaleString("pt-BR")}</Text> : null}

          <Button title={loading ? "VERIFICANDO..." : "ENTRAR"} onPress={submit} disabled={loading || !key || Boolean(lockedUntil)} />
          <Text style={styles.privacy}>
            A chave original não é salva no aplicativo. Após a tentativa, ela é removida do estado local; o servidor mantém somente o hash.
          </Text>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
