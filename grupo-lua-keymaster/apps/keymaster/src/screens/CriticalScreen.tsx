import { useEffect, useState } from "react";
import { Alert, Pressable, SafeAreaView, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { executeCriticalAction, getSystemStatus, type CriticalAction } from "../api";
import { BottomNav } from "../components/BottomNav";
import { Header } from "../components/Common";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { styles } from "../styles";

type ExecutableCriticalAction = Extract<
  CriticalAction,
  "APP1_RESTART" | "APP1_MAINTENANCE_ON" | "APP1_MAINTENANCE_OFF"
>;

export function CriticalScreen({ session, onHome, onAccounts, onMenus, onAudit }: {
  session: string;
  onHome: () => void;
  onAccounts: () => void;
  onMenus: () => void;
  onAudit: () => void;
}) {
  const [suspended, setSuspended] = useState<boolean | null>(null);
  const [pendingAction, setPendingAction] = useState<ExecutableCriticalAction | null>(null);
  const [busy, setBusy] = useState(false);
  const [busyAction, setBusyAction] = useState<ExecutableCriticalAction | null>(null);

  async function refresh() {
    try {
      setSuspended((await getSystemStatus(session)).app1Maintenance);
    } catch {
      setSuspended(null);
    }
  }

  useEffect(() => { refresh().catch(() => {}); }, [session]);

  function requestAction(action: ExecutableCriticalAction) {
    const label = action === "APP1_RESTART"
      ? "reiniciar o servidor do Aplicativo 1"
      : action === "APP1_MAINTENANCE_ON"
        ? "suspender o acesso de todos ao Aplicativo 1"
        : "reativar o acesso ao Aplicativo 1";

    const consequence = action === "APP1_MAINTENANCE_ON"
      ? " Novos logins serão bloqueados e as sessões atuais do App 1 serão encerradas. Nenhum arquivo ou conta será apagado."
      : "";

    Alert.alert(
      "Ação crítica",
      `Você está prestes a ${label}.${consequence} A próxima etapa exige LOGIN PRIVADO DEV e CHAVE DEV.`,
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Continuar",
          style: action === "APP1_MAINTENANCE_OFF" ? "default" : "destructive",
          onPress: () => setPendingAction(action)
        }
      ]
    );
  }

  const suspensionAction: ExecutableCriticalAction = suspended ? "APP1_MAINTENANCE_OFF" : "APP1_MAINTENANCE_ON";
  const suspensionBusy = busy && busyAction === suspensionAction;

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <ScrollView contentContainerStyle={styles.pageWithNav}>
          <Header title="ÁREA CRÍTICA" onBack={onHome} />

          <View style={[styles.securityCard, styles.criticalSecurity]}>
            <Text style={styles.securityTitle}>Autorização DEV obrigatória</Text>
            <Text style={styles.muted}>
              A sessão do Keymaster não basta para estas ações. Cada execução exige LOGIN PRIVADO DEV + CHAVE DEV e recebe uma autorização de uso único no servidor.
            </Text>
          </View>

          <Text style={styles.section}>ESTADO DO APLICATIVO 1</Text>
          <View style={[styles.card, suspended && styles.criticalCard]}>
            <View style={styles.statusLine}>
              <View style={suspended ? styles.redDot : styles.greenDot} />
              <Text style={styles.cardTitle}>
                {suspended == null ? "Status indisponível" : suspended ? "App 1: SUSPENSO" : "App 1: ATIVO"}
              </Text>
            </View>
            <Text style={styles.muted}>
              {suspended == null
                ? "Não foi possível confirmar o estado atual no servidor."
                : suspended
                  ? "Ninguém consegue iniciar sessão no App 1. O bloqueio permanece mesmo se o Keymaster ou o servidor reiniciarem."
                  : "Logins e sessões do App 1 estão liberados normalmente."}
            </Text>
          </View>

          <Text style={styles.section}>ACESSO GLOBAL</Text>
          <View style={styles.cardStack}>
            <View style={[styles.actionCard, suspended && { borderColor: "#1F5A2C" }]}>
              <View style={{ flex: 1 }}>
                <Text style={styles.cardTitle}>{suspended ? "Reativar Aplicativo 1" : "Suspender Aplicativo 1"}</Text>
                <Text style={styles.muted}>
                  {suspended
                    ? "Volta a permitir login. Usuários precisarão autenticar novamente porque as sessões anteriores foram revogadas."
                    : "Bloqueia novos logins e encerra imediatamente as sessões atuais, sem apagar contas ou arquivos."}
                </Text>
              </View>
              <Pressable
                disabled={busy || suspended == null}
                style={[
                  styles.actionPill,
                  suspended ? styles.actionPillSafe : styles.actionPillDanger,
                  (busy || suspended == null) && styles.buttonMuted
                ]}
                onPress={() => requestAction(suspensionAction)}
              >
                <Text style={styles.actionPillText}>
                  {suspensionBusy
                    ? suspended ? "REATIVANDO..." : "SUSPENDENDO..."
                    : suspended ? "REATIVAR" : "SUSPENDER"}
                </Text>
              </Pressable>
            </View>
          </View>

          <Text style={styles.section}>SERVIDOR</Text>
          <View style={styles.cardStack}>
            <View style={styles.actionCard}>
              <View style={{ flex: 1 }}>
                <Text style={styles.cardTitle}>Reiniciar servidor do App 1</Text>
                <Text style={styles.muted}>Envia a solicitação ao provedor configurado. Também exige uma nova autorização DEV de uso único.</Text>
              </View>
              <Pressable
                disabled={busy}
                style={[styles.actionPill, styles.actionPillDanger, busy && styles.buttonMuted]}
                onPress={() => requestAction("APP1_RESTART")}
              >
                <Text style={styles.actionPillText}>{busy && busyAction === "APP1_RESTART" ? "AGUARDE..." : "REINICIAR"}</Text>
              </Pressable>
            </View>
          </View>

          <Text style={styles.section}>PROTEÇÕES CRÍTICAS</Text>
          <View style={styles.card}>
            <Text style={styles.cardTitle}>Contas, credenciais e dispositivos</Text>
            <Text style={styles.muted}>
              Exclusão definitiva de conta, visualização/troca de credencial, desbloqueio de segurança, autorização de novo dispositivo e revogação de dispositivo usam confirmação DEV protegida na área de Contas.
            </Text>
            <Text style={styles.small}>Suspender uma conta não apaga seus dados. Excluir definitivamente remove o conteúdo pertencente àquela conta no servidor.</Text>
          </View>
        </ScrollView>
        <BottomNav current="critical" onHome={onHome} onAccounts={onAccounts} onMenus={onMenus} onAudit={onAudit} onCritical={() => {}} />
      </View>

      <DevAuthorizationModal
        visible={Boolean(pendingAction)}
        session={session}
        action={pendingAction || "APP1_RESTART"}
        title="Confirmar ação crítica"
        onCancel={() => setPendingAction(null)}
        onAuthorized={async (authorizationToken) => {
          const action = pendingAction;
          if (!action) return;
          setBusy(true);
          setBusyAction(action);
          try {
            const result = await executeCriticalAction(session, action, authorizationToken);
            setPendingAction(null);
            await refresh();
            Alert.alert(
              "Concluído",
              result.action === "APP1_RESTART"
                ? "Solicitação de reinício enviada."
                : action === "APP1_MAINTENANCE_ON"
                  ? "O App 1 foi suspenso. Novos logins estão bloqueados e as sessões anteriores foram encerradas."
                  : "O App 1 foi reativado. Novos logins estão liberados novamente."
            );
          } catch (error) {
            setPendingAction(null);
            Alert.alert(
              "Ação não concluída",
              error instanceof Error ? error.message : "A autenticação DEV foi aceita, mas o servidor não concluiu a ação."
            );
          } finally {
            setBusy(false);
            setBusyAction(null);
          }
        }}
      />
    </SafeAreaView>
  );
}
