import { Modal, ScrollView, Text, View } from "react-native";
import * as Clipboard from "expo-clipboard";
import { Button } from "./Common";
import { styles } from "../styles";

type ProtectedCredential = {
  privateLogin: string;
  credential: string;
};

export function AccountCredentialModal({
  value,
  onClose
}: {
  value: ProtectedCredential | null;
  onClose: () => void;
}) {
  return (
    <Modal visible={Boolean(value)} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.modalBackdrop}>
        <View style={styles.modalBox}>
          <Text style={styles.cardTitle}>Acesso protegido</Text>
          <Text style={styles.warning}>CONFIRMAÇÃO DEV CONCLUÍDA</Text>
          <Text style={styles.muted}>
            O nome mostrado nas listas é apenas um rótulo. O login privado e a chave aparecem somente nesta área protegida.
          </Text>

          <Text style={[styles.label, { marginTop: 18 }]}>LOGIN PRIVADO</Text>
          <ScrollView style={styles.credentialBox}>
            <Text selectable style={styles.credentialText}>{value?.privateLogin || ""}</Text>
          </ScrollView>
          <Button title="COPIAR LOGIN" onPress={async () => {
            if (value?.privateLogin) await Clipboard.setStringAsync(value.privateLogin);
          }} secondary />

          <Text style={[styles.label, { marginTop: 18 }]}>CHAVE DA CONTA</Text>
          <ScrollView style={styles.credentialBox}>
            <Text selectable style={styles.credentialText}>{value?.credential || ""}</Text>
          </ScrollView>
          <Button title="COPIAR CHAVE COMPLETA" onPress={async () => {
            if (value?.credential) await Clipboard.setStringAsync(value.credential);
          }} />
          <Button title="OCULTAR E FECHAR" onPress={onClose} secondary />
        </View>
      </View>
    </Modal>
  );
}
