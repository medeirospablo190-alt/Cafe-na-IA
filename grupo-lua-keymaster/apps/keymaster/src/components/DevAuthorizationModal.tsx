import { useEffect, useState } from "react";
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

  useEffect(() => {
    if (!visible) {
      setDevLogin("");
      setDevCredential("");
      setLoading(false);
    }
  }, [visible]);

  async function confirm() {
    if (!devLogin.trim() || !devCredential || loading) return;
    const credentialForRequest = devCredential;
    setLoading(true);
    try {
      const auth = await authorizeCriticalAction(session, action, devLogin, credentialForRequest, targetId);
      setDevCredential("");
      await onAuthorized(auth.authorizationToken);
    } catch (error) {
      setDevCredential("");
      Alert.alert("Autorização negada", error instanceof Error ? error.message : "Não foi possível confirmar a ação.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel}>
      <KeyboardAvoidingView style={styles.modalBackdrop} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <View style={[styles.modalBox, styles.devModal]}>
          <Text style={styles.devTag}>DEV • CONFIRMAÇÃO SERVER-SIDE</Text>
          <Text style={styles.cardTitle}>{title}</Text>
          <Text style={styles.muted}>A credencial abaixo é usada apenas nesta confirmação e é removida do estado local depois da tentativa.</Text>
          <TextInput
            value={devLogin}
            onChangeText={setDevLogin}
            style={styles.input}
            placeholder="Login DEV"
            placeholderTextColor="#666"
            autoCapitalize="none"
            autoCorrect={false}
          />
          <TextInput
            value={devCredential}
            onChangeText={setDevCredential}
            style={styles.input}
            placeholder="DEV KEY"
            placeholderTextColor="#666"
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
            spellCheck={false}
          />
          <Button title={loading ? "CONFIRMANDO..." : "AUTORIZAR UMA VEZ"} onPress={confirm} disabled={loading || !devLogin.trim() || !devCredential} danger />
          <Button title="CANCELAR" onPress={onCancel} secondary disabled={loading} />
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}
