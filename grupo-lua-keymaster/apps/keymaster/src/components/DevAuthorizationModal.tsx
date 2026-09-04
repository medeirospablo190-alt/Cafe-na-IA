import { useEffect, useMemo, useRef, useState } from "react";
import { Alert, KeyboardAvoidingView, Modal, Platform, Text, TextInput, View } from "react-native";
import { authorizeCriticalAction, type CriticalAction } from "../api";
import { Button } from "./Common";
import { styles } from "../styles";

export function DevAuthorizationModal({
  visible,
  session,
  action,
  targetId,
  title,
  onCancel,
  onAuthorized
}: {
  visible: boolean;
  session: string;
  action: CriticalAction;
  targetId?: string;
  title: string;
  onCancel: () => void;
  onAuthorized: (authorizationToken: string) => Promise<void>;
}) {
  const [devLogin, setDevLogin] = useState("");
  const [devCredential, setDevCredential] = useState("");
  const [loading, setLoading] = useState(false);
  const requestLock = useRef(false);

  const safeTitle = useMemo(() => {
    const value = String(title || "").trim();
    if (!value || /\b(undefined|null)\b/i.test(value)) return "Confirmar ação protegida";
    return value;
  }, [title]);

  useEffect(() => {
    if (!visible) {
      requestLock.current = false;
      setDevLogin("");
      setDevCredential("");
      setLoading(false);
    }
  }, [visible]);

  async function confirm() {
    if (!devLogin.trim() || !devCredential || requestLock.current) return;
    const credentialForRequest = devCredential;
    const identityForRequest = devLogin.trim();
    requestLock.current = true;
    setLoading(true);

    let authorizationToken = "";
    try {
      const auth = await authorizeCriticalAction(session, action, identityForRequest, credentialForRequest, targetId);
      authorizationToken = auth.authorizationToken;
    } catch (error) {
      setDevCredential("");
      requestLock.current = false;
      setLoading(false);
      Alert.alert("Autorização DEV negada", error instanceof Error ? error.message : "Login privado/chave DEV não foram aceitos pelo servidor.");
      return;
    }

    // A chave DEV não permanece no estado durante a execução da operação.
    setDevCredential("");
    try {
      await onAuthorized(authorizationToken);
    } catch (error) {
      Alert.alert(
        "Ação não concluída",
        error instanceof Error ? error.message : "A autenticação DEV foi aceita, mas a operação protegida não foi concluída."
      );
    } finally {
      requestLock.current = false;
      setLoading(false);
    }
  }

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={() => { if (!requestLock.current) onCancel(); }}>
      <KeyboardAvoidingView
        style={styles.modalBackdrop}
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <View style={[styles.modalBox, styles.devModal]}>
          <Text style={styles.devTag}>DEV • CONFIRMAÇÃO SERVER-SIDE</Text>
          <Text style={styles.cardTitle}>{safeTitle}</Text>
          <Text style={styles.muted}>
            Digite o login privado da conta DEV e a chave DEV. O nome visível não substitui o login nesta confirmação. A chave é removida do estado local depois da tentativa.
          </Text>
          <TextInput
            value={devLogin}
            onChangeText={setDevLogin}
            style={styles.input}
            placeholder="LOGIN PRIVADO DEV"
            placeholderTextColor="#666"
            autoCapitalize="none"
            autoCorrect={false}
            spellCheck={false}
            editable={!loading}
            returnKeyType="next"
          />
          <TextInput
            value={devCredential}
            onChangeText={setDevCredential}
            style={styles.input}
            placeholder="CHAVE DEV"
            placeholderTextColor="#666"
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            spellCheck={false}
            editable={!loading}
            returnKeyType="done"
            onSubmitEditing={() => { confirm().catch(() => {}); }}
          />
          <Button title={loading ? "CONFIRMANDO..." : "AUTORIZAR UMA VEZ"} onPress={confirm} disabled={loading || !devLogin.trim() || !devCredential} danger />
          <Button title="CANCELAR" onPress={onCancel} secondary disabled={loading} />
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}
