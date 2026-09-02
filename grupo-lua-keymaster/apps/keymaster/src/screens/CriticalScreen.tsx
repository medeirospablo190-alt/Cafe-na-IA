import { useEffect, useState } from "react";
import { Alert, Pressable, SafeAreaView, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { executeCriticalAction, getSystemStatus, type CriticalAction } from "../api";
import { Header } from "../components/Common";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { styles } from "../styles";

type ExecutableCriticalAction = Exclude<CriticalAction, "DELETE_APP1_ACCOUNT">;

export function CriticalScreen({ session, onBack }: { session: string; onBack: () => void }) {
  const [maintenance, setMaintenance] = useState<boolean | null>(null);
  const [pendingAction, setPendingAction] = useState<ExecutableCriticalAction | null>(null);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    try {
      setMaintenance((await getSystemStatus(session)).app1Maintenance);
    } catch {
      setMaintenance(null);
    }
  }

  useEffect(() => { refresh().catch(() => {}); }, [session]);

  function requestAction(action: ExecutableCriticalAction) {
    const label = action === "APP1_RESTART"
      ? "reiniciar o Aplicativo 1"
      : action === "APP1_MAINTENANCE_ON"
        ? "colocar o Aplicativo 1 em manutenção"
        : "retirar o Aplicativo 1 da manutenção";
    Alert.alert("Ação crítica", `Você está prestes a ${label}. A próxima etapa exige login e credencial DEV.`, [
      { text: "Cancelar", style: "cancel" },
      { text: "Continuar", style: action === "APP1_MAINTENANCE_OFF" ? "default" : "destructive", onPress: () => setPendingAction(action) }
    ]);
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.page}>
        <Header title="ÁREA CRÍTICA" onBack={onBack} />

        <View style={[styles.securityCard, styles.criticalSecurity]}>
          <Text style={styles.securityTitle}>Proteção em duas etapas</Text>
          <Text style={styles.muted}>A sessão Keymaster sozinha não executa estas ações. O servidor exige uma conta DEV ativa e gera um token de uso único com validade curta.</Text>
        </View>

        <Text style={styles.section}>ESTADO DO APLICATIVO 1</Text>
        <View style={styles.card}>
          <View style={styles.statusLine}>
            <View style={maintenance ? styles.redDot : styles.greenDot} />
            <Text style={styles.cardTitle}>{maintenance == null ? "Status indisponível" : maintenance ? "Em manutenção" : "Online"}</Text>
          </View>
          <Text style={styles.muted}>O estado é lido do servidor; alterar relógio ou interface do celular não muda esta condição.</Text>
        </View>

        <Text style={styles.section}>CONTROLES</Text>
        <View style={styles.cardStack}>
          <View style={styles.actionCard}>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>{maintenance ? "Encerrar manutenção" : "Ativar manutenção"}</Text>
              <Text style={styles.muted}>{maintenance ? "Libera novamente login e sessões do App 1." : "Bloqueia login e uso de sessões do App 1 no servidor."}</Text>
            </View>
            <Pressable
              disabled={busy || maintenance == null}
              style={[styles.actionPill, maintenance ? styles.actionPillSafe : styles.actionPillDanger]}
              onPress={() => requestAction(maintenance ? "APP1_MAINTENANCE_OFF" : "APP1_MAINTENANCE_ON")}
            >
              <Text style={styles.actionPillText}>{maintenance ? "LIBERAR" : "ATIVAR"}</Text>
            </Pressable>
          </View>

          <View style={styles.actionCard}>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Reiniciar servidor do App 1</Text>
              <Text style={styles.muted}>Usa webhook privado do provedor quando configurado no servidor.</Text>
            </View>
            <Pressable disabled={busy} style={[styles.actionPill, styles.actionPillDanger]} onPress={() => requestAction("APP1_RESTART")}>
              <Text style={styles.actionPillText}>REINICIAR</Text>
            </Pressable>
          </View>
        </View>

        <Text style={styles.section}>PRÓXIMAS CAMADAS</Text>
        <View style={[styles.card, styles.lockedCard]}>
          <Text style={styles.cardTitle}>Exclusão global e recuperação crítica</Text>
          <Text style={styles.muted}>A autorização de uso único já está preparada. A execução global ficará habilitada quando as tabelas de Social, Chats, Arquivos e FREE/VIP existirem para que o escopo seja preciso e auditável.</Text>
          <Text style={styles.locked}>BLOQUEADA ATÉ O MODELO DE DADOS DO APP 1</Text>
        </View>
      </ScrollView>

      <DevAuthorizationModal
        visible={Boolean(pendingAction)}
        session={session}
        action={pendingAction || "APP1_RESTART"}
        title="Confirmar ação crítica"
        onCancel={() => setPendingAction(null)}
        onAuthorized={async (authorizationToken) => {
          if (!pendingAction) return;
          setBusy(true);
          try {
            const result = await executeCriticalAction(session, pendingAction, authorizationToken);
            setPendingAction(null);
            await refresh();
            Alert.alert("Concluído", result.action === "APP1_RESTART" ? "Solicitação de reinício enviada." : "Estado de manutenção atualizado pelo servidor.");
          } finally {
            setBusy(false);
          }
        }}
      />
    </SafeAreaView>
  );
}
