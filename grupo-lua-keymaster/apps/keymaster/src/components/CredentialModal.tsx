import { Modal, ScrollView, Text, View } from "react-native";
import * as Clipboard from "expo-clipboard";
import { Button } from "./Common";
import { styles } from "../styles";

export function CredentialModal({ credential, onClose }: { credential: string | null; onClose: () => void }) {
  return (
    <Modal visible={Boolean(credential)} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.modalBackdrop}>
        <View style={styles.modalBox}>
          <Text style={styles.cardTitle}>Credencial criada</Text>
          <Text style={styles.warning}>EXIBIÇÃO ÚNICA</Text>
          <Text style={styles.muted}>Depois de fechar, o servidor não consegue revelar esta chave novamente.</Text>
          <ScrollView style={styles.credentialBox}><Text selectable style={styles.credentialText}>{credential}</Text></ScrollView>
          <Button title="COPIAR CHAVE COMPLETA" onPress={async () => {
            if (credential) await Clipboard.setStringAsync(credential);
          }} />
          <Button title="JÁ SALVEI • FECHAR" onPress={onClose} secondary />
        </View>
      </View>
    </Modal>
  );
}
