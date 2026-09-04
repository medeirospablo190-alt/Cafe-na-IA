import { useEffect, useState } from "react";
import { ActivityIndicator, Alert, FlatList, Pressable, SafeAreaView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { listAudit, type AuditEvent } from "../api";
import { BottomNav } from "../components/BottomNav";
import { Header } from "../components/Common";
import { styles } from "../styles";

const ACTION_LABELS: Record<string, string> = {
  KEYMASTER_LOGIN_SUCCESS: "Login Keymaster autorizado",
  KEYMASTER_LOGIN_FAILED: "Tentativa Keymaster inválida",
  KEYMASTER_LOGIN_BLOCKED: "Tentativa durante bloqueio",
  KEYMASTER_DEVICE_LOCKED_24H: "Dispositivo bloqueado por 24h",
  APP1_ACCOUNT_CREATED: "Conta criada",
  APP1_ACCOUNT_SUSPENDED: "Conta suspensa",
  APP1_ACCOUNT_RESTORED: "Conta restabelecida",
  APP1_CREDENTIAL_ROTATED: "Chave da conta alterada",
  APP1_CREDENTIAL_REVEALED: "Login e chave visualizados",
  APP1_ACCOUNT_DELETED: "Conta excluída",
  APP1_SESSION_REVOKED: "Sessão revogada",
  APP1_SESSIONS_REVOKED_ALL: "Sessões revogadas",
  APP1_DEVICE_IDENTITY_RECOVERED: "Identidade do mesmo dispositivo recuperada",
  MENU_CREATED: "Menu cadastrado",
  MENU_UPDATED: "Menu atualizado",
  MENU_SUSPENDED: "Menu suspenso",
  MENU_RESTORED: "Menu restabelecido",
  MENU_DELETED: "Menu excluído",
  MENU_KEY_CREATED: "Chave de menu criada",
  MENU_KEY_SUSPEND: "Chave de menu suspensa",
  MENU_KEY_RESTORE: "Chave de menu liberada",
  MENU_KEY_REVOKE: "Chave de menu revogada",
  MENU_KEY_PERMANENT: "Chave FREE convertida para VIP",
  MENU_KEY_DURATION_CHANGED: "Duração FREE alterada",
  CRITICAL_AUTHORIZATION_CREATED: "Autorização crítica criada",
  APP1_MAINTENANCE_ON: "Manutenção ativada",
  APP1_MAINTENANCE_OFF: "Manutenção encerrada",
  APP1_RESTART_REQUESTED: "Reinício solicitado"
};

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function eventTitle(event: AuditEvent) {
  return ACTION_LABELS[event.action] || event.action.replaceAll("_", " ");
}

export function AuditScreen({ session, onHome, onAccounts, onMenus, onCritical }: {
  session: string;
  onHome: () => void;
  onAccounts: () => void;
  onMenus: () => void;
  onCritical: () => void;
}) {
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [nextBefore, setNextBefore] = useState<string | null>(null);

  async function load(reset = false) {
    try {
      if (reset) setLoading(true);
      else setLoadingMore(true);
      const result = await listAudit(session, reset ? undefined : nextBefore || undefined);
      setEvents((current) => reset ? result.events : [...current, ...result.events]);
      setNextBefore(result.nextBefore);
    } catch (error) {
      Alert.alert("Falha na auditoria", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }

  useEffect(() => { load(true).catch(() => {}); }, [session]);

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <View style={styles.screenBody}>
          <Header title="AUDITORIA" onBack={onHome} />
          <View style={styles.listHeaderCompact}>
            <View style={{ flex: 1 }}>
              <Text style={styles.screenTitle}>Histórico protegido</Text>
              <Text style={styles.muted}>Eventos administrativos registrados pelo servidor. Logins privados não aparecem nesta tela.</Text>
            </View>
            <Pressable style={styles.iconAction} onPress={() => load(true)}>
              <Text style={styles.iconActionText}>↻</Text>
            </Pressable>
          </View>

          {loading ? <ActivityIndicator style={{ marginTop: 30 }} /> : (
            <FlatList
              data={events}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.auditList}
              ListEmptyComponent={<Text style={styles.empty}>Nenhum evento registrado.</Text>}
              renderItem={({ item }) => (
                <View style={[styles.auditCard, item.actor_kind === "DEV" && styles.auditCardDev]}>
                  <View style={styles.auditTop}>
                    <View style={[styles.auditDot, item.actor_kind === "DEV" && styles.auditDotDev]} />
                    <Text style={styles.auditTitle}>{eventTitle(item)}</Text>
                    <Text style={styles.auditTime}>{formatDate(item.created_at)}</Text>
                  </View>
                  <Text style={styles.auditMeta}>
                    Autor: {item.actor_name || item.actor_kind}
                    {item.target_name ? ` • Alvo: ${item.target_name}` : item.target_kind ? ` • Alvo: ${item.target_kind}` : ""}
                  </Text>
                  {item.action === "KEYMASTER_DEVICE_LOCKED_24H" ? (
                    <Text style={styles.auditDanger}>Bloqueio de segurança aplicado pelo servidor.</Text>
                  ) : null}
                </View>
              )}
              ListFooterComponent={nextBefore ? (
                <Pressable disabled={loadingMore} style={styles.loadMore} onPress={() => load(false)}>
                  <Text style={styles.loadMoreText}>{loadingMore ? "CARREGANDO..." : "CARREGAR MAIS"}</Text>
                </Pressable>
              ) : <View style={{ height: 18 }} />}
            />
          )}
        </View>
        <BottomNav current="audit" onHome={onHome} onAccounts={onAccounts} onMenus={onMenus} onAudit={() => {}} onCritical={onCritical} />
      </View>
    </SafeAreaView>
  );
}
