import { useEffect, useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View
} from "react-native";
import {
  type Account,
  type AccountLoginAttempt,
  type AccountSecurity,
  type AccountSecurityDevice,
  type CriticalAction,
  cancelDeviceEnrollment,
  getAccountSecurity,
  openDeviceEnrollment,
  revokeApp1Device,
  unlockAccountSecurity
} from "../api";
import { DevAuthorizationModal } from "./DevAuthorizationModal";

type ProtectedAction = Extract<
  CriticalAction,
  "UNLOCK_APP1_ACCOUNT" | "AUTHORIZE_APP1_DEVICE" | "REVOKE_APP1_DEVICE"
>;

type CriticalRequest = {
  action: ProtectedAction;
  title: string;
  deviceId?: string;
};

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function lockReason(value?: string | null) {
  if (value === "INVALID_CREDENTIALS_3") return "3 credenciais inválidas";
  if (value === "UNAUTHORIZED_DEVICE_3") return "3 tentativas em dispositivo não autorizado";
  if (value === "DEVICE_PROOF_INVALID_3") return "3 falhas na prova do dispositivo";
  return value || "—";
}

function attemptLabel(value: string) {
  const labels: Record<string, string> = {
    SUCCESS: "ACESSO AUTORIZADO",
    INVALID_CREDENTIAL: "CREDENCIAL INVÁLIDA",
    ACCOUNT_LOCKED: "CONTA BLOQUEADA",
    ACCOUNT_SUSPENDED: "CONTA SUSPENSA",
    ACCOUNT_DELETED: "CONTA REMOVIDA",
    UNAUTHORIZED_DEVICE: "DISPOSITIVO NÃO AUTORIZADO",
    DEVICE_PROOF_INVALID: "PROVA DO DISPOSITIVO INVÁLIDA",
    INTEGRITY_REJECTED: "INTEGRIDADE RECUSADA"
  };
  return labels[value] || value;
}

function attemptTone(value: string) {
  if (value === "SUCCESS") return local.success;
  if (["ACCOUNT_LOCKED", "UNAUTHORIZED_DEVICE", "DEVICE_PROOF_INVALID", "INTEGRITY_REJECTED"].includes(value)) return local.danger;
  return local.warning;
}

function remaining(expiresAt?: string | null, now = Date.now()) {
  if (!expiresAt) return 0;
  const ms = new Date(expiresAt).getTime() - now;
  return Number.isFinite(ms) ? Math.max(0, Math.ceil(ms / 1000)) : 0;
}

function remainingLabel(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(rest).padStart(2, "0")}`;
}

function DeviceCard({ device, onRevoke }: {
  device: AccountSecurityDevice;
  onRevoke: () => void;
}) {
  const active = device.status === "ACTIVE";
  return (
    <View style={local.itemCard}>
      <View style={local.rowBetween}>
        <View style={{ flex: 1 }}>
          <View style={local.inlineRow}>
            <Text style={local.itemTitle}>{device.deviceLabel || device.platform || "Dispositivo"}</Text>
            {device.isPrimary ? <Text style={local.primaryTag}>PRINCIPAL</Text> : null}
          </View>
          <Text style={local.meta}>{device.platform.toUpperCase()} • {device.deviceHint || "sem identificação"}</Text>
        </View>
        <Text style={active ? local.success : local.off}>{active ? "ATIVO" : "REVOGADO"}</Text>
      </View>
      <Text style={local.meta}>Autorizado {formatDate(device.authorizedAt)}</Text>
      <Text style={local.meta}>Última atividade {formatDate(device.lastSeenAt)} • rede {device.networkHint || "—"}</Text>
      {active ? (
        <Pressable style={local.smallDangerButton} onPress={onRevoke}>
          <Text style={local.smallDangerText}>REVOGAR DISPOSITIVO</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function AttemptCard({ attempt }: { attempt: AccountLoginAttempt }) {
  const failureCount = Number(attempt.metadata?.failureCount || 0);
  return (
    <View style={local.itemCard}>
      <View style={local.rowBetween}>
        <Text style={[local.attemptResult, attemptTone(attempt.result)]}>{attemptLabel(attempt.result)}</Text>
        <Text style={local.meta}>{formatDate(attempt.createdAt)}</Text>
      </View>
      <Text style={local.meta}>Dispositivo {attempt.deviceHint || "—"} • {attempt.platform || "—"}</Text>
      <Text style={local.meta}>Rede {attempt.networkHint || "—"} • credencial {attempt.credentialHint || "—"}</Text>
      <Text style={local.meta}>Integridade {attempt.integrityVerified ? "verificada" : "não verificada"}{failureCount ? ` • tentativa ${Math.min(failureCount, 3)}/3` : ""}</Text>
    </View>
  );
}

export function AccountSecurityModal({
  visible,
  session,
  account,
  onClose,
  onChanged
}: {
  visible: boolean;
  session: string;
  account: Account | null;
  onClose: () => void;
  onChanged: () => Promise<void> | void;
}) {
  const [security, setSecurity] = useState<AccountSecurity | null>(null);
  const [loading, setLoading] = useState(false);
  const [critical, setCritical] = useState<CriticalRequest | null>(null);
  const [now, setNow] = useState(Date.now());

  async function reload() {
    if (!account) return;
    setLoading(true);
    try {
      const result = await getAccountSecurity(session, account.id);
      setSecurity({
        account: result.account,
        devices: result.devices,
        attempts: result.attempts,
        enrollments: result.enrollments
      });
    } catch (error) {
      Alert.alert("Segurança indisponível", error instanceof Error ? error.message : "Não foi possível carregar os dados de segurança.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (visible && account) reload().catch(() => {});
    if (!visible) {
      setSecurity(null);
      setCritical(null);
    }
  }, [visible, account?.id, session]);

  useEffect(() => {
    if (!visible) return;
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, [visible]);

  const pendingEnrollment = useMemo(
    () => security?.enrollments.find((item) => item.status === "PENDING") || null,
    [security?.enrollments]
  );
  const pendingSeconds = remaining(pendingEnrollment?.expires_at, now);
  const activeDevices = security?.devices.filter((item) => item.status === "ACTIVE").length || 0;

  async function cancelPending() {
    if (!account || !pendingEnrollment) return;
    Alert.alert("Cancelar autorização", "Cancelar agora a autorização pendente para novo dispositivo?", [
      { text: "Voltar", style: "cancel" },
      {
        text: "Cancelar autorização",
        style: "destructive",
        onPress: async () => {
          try {
            await cancelDeviceEnrollment(session, account.id);
            await reload();
            await onChanged();
          } catch (error) {
            Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível cancelar.");
          }
        }
      }
    ]);
  }

  async function executeProtected(authorizationToken: string) {
    if (!account || !critical) return;
    try {
      if (critical.action === "UNLOCK_APP1_ACCOUNT") {
        await unlockAccountSecurity(session, account.id, authorizationToken);
      } else if (critical.action === "AUTHORIZE_APP1_DEVICE") {
        await openDeviceEnrollment(session, account.id, authorizationToken);
      } else if (critical.action === "REVOKE_APP1_DEVICE" && critical.deviceId) {
        await revokeApp1Device(session, account.id, critical.deviceId, authorizationToken);
      }
      setCritical(null);
      await reload();
      await onChanged();
    } catch (error) {
      setCritical(null);
      Alert.alert("Operação não concluída", error instanceof Error ? error.message : "O servidor recusou a operação.");
    }
  }

  return (
    <>
      <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
        <View style={local.backdrop}>
          <View style={local.modal}>
            <View style={local.header}>
              <View style={{ flex: 1 }}>
                <Text style={local.eyebrow}>SEGURANÇA DA CONTA</Text>
                <Text style={local.title}>{account?.name || "Conta"}</Text>
              </View>
              <Pressable onPress={onClose} style={local.closeButton}><Text style={local.closeText}>✕</Text></Pressable>
            </View>

            {loading && !security ? <ActivityIndicator style={{ marginTop: 28 }} /> : security ? (
              <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={local.content}>
                <View style={[local.summaryCard, security.account.status === "LOCKED_SECURITY" && local.summaryDanger]}>
                  <View style={local.rowBetween}>
                    <Text style={local.summaryTitle}>Estado</Text>
                    <Text style={security.account.status === "ACTIVE" ? local.success : local.danger}>{security.account.status}</Text>
                  </View>
                  <Text style={local.meta}>Erros de credencial: {security.account.failed_login_attempts}/3</Text>
                  <Text style={local.meta}>Erros de dispositivo: {security.account.failed_device_attempts}/3</Text>
                  {security.account.status === "LOCKED_SECURITY" ? (
                    <>
                      <Text style={local.reason}>Motivo: {lockReason(security.account.security_lock_reason)}</Text>
                      <Text style={local.meta}>Bloqueada em {formatDate(security.account.security_locked_at)}</Text>
                      <Pressable
                        style={local.primaryDangerButton}
                        onPress={() => setCritical({
                          action: "UNLOCK_APP1_ACCOUNT",
                          title: `Liberar ${security.account.name}`
                        })}
                      >
                        <Text style={local.primaryDangerText}>LIBERAR CONTA COM CONFIRMAÇÃO DEV</Text>
                      </Pressable>
                    </>
                  ) : null}
                </View>

                <View style={local.sectionHeader}>
                  <View>
                    <Text style={local.sectionTitle}>DISPOSITIVOS</Text>
                    <Text style={local.sectionHint}>{activeDevices}/2 ativos</Text>
                  </View>
                  <Pressable onPress={() => reload()}><Text style={local.refresh}>ATUALIZAR</Text></Pressable>
                </View>

                {pendingEnrollment ? (
                  <View style={local.enrollmentCard}>
                    <Text style={local.enrollmentTag}>AUTORIZAÇÃO PENDENTE</Text>
                    <Text style={local.enrollmentTime}>{pendingSeconds > 0 ? remainingLabel(pendingSeconds) : "EXPIRANDO"}</Text>
                    <Text style={local.meta}>Máximo de 10 minutos. Assim que um novo dispositivo for registrado com sucesso, esta autorização é consumida imediatamente.</Text>
                    <Pressable style={local.smallDangerButton} onPress={cancelPending}>
                      <Text style={local.smallDangerText}>CANCELAR AUTORIZAÇÃO</Text>
                    </Pressable>
                  </View>
                ) : (
                  <Pressable
                    style={[local.authorizeButton, activeDevices >= 2 && local.disabled]}
                    disabled={activeDevices >= 2}
                    onPress={() => setCritical({
                      action: "AUTHORIZE_APP1_DEVICE",
                      title: `Autorizar novo dispositivo para ${security.account.name}`
                    })}
                  >
                    <Text style={local.authorizeText}>{activeDevices >= 2 ? "LIMITE DE 2 DISPOSITIVOS ATIVOS" : "AUTORIZAR NOVO DISPOSITIVO • 10 MIN"}</Text>
                  </Pressable>
                )}

                {security.devices.length === 0 ? <Text style={local.empty}>Nenhum dispositivo registrado.</Text> : security.devices.map((device) => (
                  <DeviceCard
                    key={device.id}
                    device={device}
                    onRevoke={() => Alert.alert(
                      "Revogar dispositivo",
                      `Revogar ${device.deviceLabel || device.platform}? As sessões deste aparelho serão encerradas.`,
                      [
                        { text: "Cancelar", style: "cancel" },
                        {
                          text: "Continuar",
                          style: "destructive",
                          onPress: () => setCritical({
                            action: "REVOKE_APP1_DEVICE",
                            title: `Revogar dispositivo de ${security.account.name}`,
                            deviceId: device.id
                          })
                        }
                      ]
                    )}
                  />
                ))}

                <View style={local.sectionHeader}>
                  <View>
                    <Text style={local.sectionTitle}>TENTATIVAS DE ACESSO</Text>
                    <Text style={local.sectionHint}>Somente fingerprints protegidos; nenhuma chave completa é exibida.</Text>
                  </View>
                </View>
                {security.attempts.length === 0 ? <Text style={local.empty}>Nenhuma tentativa registrada.</Text> : security.attempts.map((attempt) => (
                  <AttemptCard key={attempt.id} attempt={attempt} />
                ))}

                <View style={local.sectionHeader}>
                  <View>
                    <Text style={local.sectionTitle}>HISTÓRICO DE AUTORIZAÇÕES</Text>
                    <Text style={local.sectionHint}>PENDING • CONSUMED • EXPIRED • CANCELLED</Text>
                  </View>
                </View>
                {security.enrollments.length === 0 ? <Text style={local.empty}>Nenhuma autorização registrada.</Text> : security.enrollments.map((item) => (
                  <View key={item.id} style={local.itemCard}>
                    <View style={local.rowBetween}>
                      <Text style={item.status === "CONSUMED" ? local.success : item.status === "PENDING" ? local.warning : local.off}>{item.status}</Text>
                      <Text style={local.meta}>{formatDate(item.created_at)}</Text>
                    </View>
                    <Text style={local.meta}>Expira {formatDate(item.expires_at)}</Text>
                    {item.consumed_at ? <Text style={local.meta}>Consumida {formatDate(item.consumed_at)}</Text> : null}
                    {item.cancelled_at ? <Text style={local.meta}>Cancelada {formatDate(item.cancelled_at)}</Text> : null}
                  </View>
                ))}
              </ScrollView>
            ) : (
              <Text style={local.empty}>Dados de segurança indisponíveis.</Text>
            )}
          </View>
        </View>
      </Modal>

      <DevAuthorizationModal
        visible={Boolean(critical)}
        session={session}
        action={critical?.action || "UNLOCK_APP1_ACCOUNT"}
        targetId={account?.id}
        title={critical?.title || "Confirmar operação de segurança"}
        onCancel={() => setCritical(null)}
        onAuthorized={executeProtected}
      />
    </>
  );
}

const local = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.9)", justifyContent: "flex-end" },
  modal: { maxHeight: "94%", minHeight: "78%", backgroundColor: "#070709", borderTopLeftRadius: 24, borderTopRightRadius: 24, borderWidth: 1, borderColor: "#29292E", paddingHorizontal: 17, paddingTop: 17 },
  header: { flexDirection: "row", alignItems: "flex-start", gap: 10, paddingBottom: 12, borderBottomWidth: 1, borderBottomColor: "#1D1D21" },
  eyebrow: { color: "#77777E", fontSize: 9, fontWeight: "900", letterSpacing: 1.4 },
  title: { color: "#FFFFFF", fontSize: 22, fontWeight: "900", marginTop: 4 },
  closeButton: { width: 38, height: 38, borderRadius: 12, borderWidth: 1, borderColor: "#303035", alignItems: "center", justifyContent: "center" },
  closeText: { color: "#B8B8BE", fontSize: 18 },
  content: { paddingTop: 13, paddingBottom: 34 },
  summaryCard: { borderRadius: 17, backgroundColor: "#0A0A0D", borderWidth: 1, borderColor: "#27272C", padding: 15 },
  summaryDanger: { borderColor: "#5B2025", backgroundColor: "#110708" },
  summaryTitle: { color: "#FFFFFF", fontSize: 15, fontWeight: "900" },
  rowBetween: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  inlineRow: { flexDirection: "row", alignItems: "center", gap: 7, flexWrap: "wrap" },
  meta: { color: "#74747B", fontSize: 10, lineHeight: 15, marginTop: 5 },
  reason: { color: "#FF8B8F", fontSize: 11, lineHeight: 16, fontWeight: "800", marginTop: 9 },
  success: { color: "#55E27D", fontSize: 9, fontWeight: "900" },
  warning: { color: "#FFB340", fontSize: 9, fontWeight: "900" },
  danger: { color: "#FF5148", fontSize: 9, fontWeight: "900" },
  off: { color: "#77777E", fontSize: 9, fontWeight: "900" },
  primaryDangerButton: { minHeight: 46, borderRadius: 12, backgroundColor: "#D32631", alignItems: "center", justifyContent: "center", paddingHorizontal: 12, marginTop: 13 },
  primaryDangerText: { color: "#FFFFFF", fontSize: 10, fontWeight: "900", textAlign: "center" },
  sectionHeader: { flexDirection: "row", alignItems: "flex-end", justifyContent: "space-between", gap: 10, marginTop: 21, marginBottom: 9 },
  sectionTitle: { color: "#85858C", fontSize: 9, fontWeight: "900", letterSpacing: 1.3 },
  sectionHint: { color: "#5F5F65", fontSize: 9, lineHeight: 13, marginTop: 4, maxWidth: 280 },
  refresh: { color: "#B875FF", fontSize: 9, fontWeight: "900", paddingVertical: 6 },
  itemCard: { borderRadius: 14, borderWidth: 1, borderColor: "#242429", backgroundColor: "#0A0A0C", padding: 13, marginBottom: 8 },
  itemTitle: { color: "#ECECF0", fontSize: 12, fontWeight: "800" },
  primaryTag: { color: "#C791FF", backgroundColor: "#1A1025", borderRadius: 6, paddingHorizontal: 6, paddingVertical: 2, fontSize: 7, fontWeight: "900" },
  smallDangerButton: { alignSelf: "flex-start", borderRadius: 9, borderWidth: 1, borderColor: "#552126", backgroundColor: "#130708", paddingHorizontal: 10, paddingVertical: 8, marginTop: 9 },
  smallDangerText: { color: "#FF5A52", fontSize: 8, fontWeight: "900" },
  authorizeButton: { borderRadius: 13, borderWidth: 1, borderColor: "#6D3AA4", backgroundColor: "#160D20", minHeight: 47, alignItems: "center", justifyContent: "center", paddingHorizontal: 12, marginBottom: 9 },
  authorizeText: { color: "#CB98FF", fontSize: 9, fontWeight: "900", textAlign: "center" },
  disabled: { opacity: 0.35 },
  enrollmentCard: { borderRadius: 15, borderWidth: 1, borderColor: "#6E4B1C", backgroundColor: "#130E06", padding: 14, marginBottom: 9 },
  enrollmentTag: { color: "#FFB340", fontSize: 9, fontWeight: "900", letterSpacing: 1 },
  enrollmentTime: { color: "#FFFFFF", fontSize: 25, fontWeight: "900", marginTop: 5 },
  attemptResult: { fontSize: 9, fontWeight: "900", flex: 1 },
  empty: { color: "#67676D", textAlign: "center", paddingVertical: 20, fontSize: 11 }
});
