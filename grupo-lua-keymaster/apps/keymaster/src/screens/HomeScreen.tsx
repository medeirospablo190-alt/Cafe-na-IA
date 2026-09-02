import { useEffect, useState } from "react";
import { Pressable, SafeAreaView, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { API_URL } from "../config";
import { getSystemStatus } from "../api";
import { Header } from "../components/Common";
import { styles } from "../styles";

export function HomeScreen({ session, onAccounts, onCritical, onLogout }: {
  session: string;
  onAccounts: () => void;
  onCritical: () => void;
  onLogout: () => void;
}) {
  const [maintenance, setMaintenance] = useState<boolean | null>(null);

  useEffect(() => {
    getSystemStatus(session).then((r) => setMaintenance(r.app1Maintenance)).catch(() => setMaintenance(null));
  }, [session]);

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.page}>
        <Header title="KEYMASTER" onLogout={onLogout} />

        <View style={styles.securityCard}>
          <View style={styles.statusLine}>
            <View style={styles.greenDot} />
            <Text style={styles.securityTitle}>Sessão protegida e validada</Text>
          </View>
          <Text style={styles.muted}>A chave mestre não fica armazenada no APK/IPA nem no SecureStore.</Text>
          <Text style={styles.small}>Servidor: {API_URL}</Text>
        </View>

        <View style={styles.summaryGrid}>
          <View style={styles.summaryCard}>
            <Text style={styles.summaryLabel}>APP 1</Text>
            <Text style={[styles.summaryValue, maintenance ? styles.redText : styles.greenText]}>
              {maintenance == null ? "—" : maintenance ? "MANUTENÇÃO" : "ONLINE"}
            </Text>
          </View>
          <View style={styles.summaryCard}>
            <Text style={styles.summaryLabel}>ROLES</Text>
            <Text style={styles.summaryValue}>ADM + DEV</Text>
          </View>
        </View>

        <Text style={styles.section}>ACESSOS DO APLICATIVO 1</Text>
        <Pressable style={styles.card} onPress={onAccounts}>
          <Text style={styles.cardTitle}>Administradores e DEVs</Text>
          <Text style={styles.muted}>Criar, suspender, liberar, rotacionar e excluir contas com confirmação apropriada.</Text>
          <Text style={styles.cardArrow}>›</Text>
        </Pressable>

        <Text style={styles.section}>AÇÕES CRÍTICAS</Text>
        <Pressable style={[styles.card, styles.criticalCard]} onPress={onCritical}>
          <Text style={styles.cardTitle}>Área DEV protegida</Text>
          <Text style={styles.muted}>Manutenção e reinício exigem reautenticação DEV e autorização server-side de uso único.</Text>
          <Text style={styles.criticalLabel}>REAUTENTICAÇÃO OBRIGATÓRIA</Text>
          <Text style={[styles.cardArrow, styles.redText]}>›</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}
