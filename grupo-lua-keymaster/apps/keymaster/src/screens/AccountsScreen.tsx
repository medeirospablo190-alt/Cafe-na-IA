import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Alert, FlatList, Modal, Pressable, SafeAreaView, ScrollView, Text, TextInput, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import {
  type Account,
  type AccountRole,
  type AccountSession,
  createAccount,
  deleteAccount,
  listAccounts,
  listAccountSessions,
  revealAccountCredential,
  revokeAccountSession,
  revokeAllAccountSessions,
  rotateCredential,
  setAccountState
} from "../api";
import { BottomNav } from "../components/BottomNav";
import { Button, Header } from "../components/Common";
import { AccountCredentialModal } from "../components/AccountCredentialModal";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { AccountSecurityModal } from "../components/AccountSecurityModal";
import { styles } from "../styles";

type RoleFilter = "ALL" | AccountRole;
type StatusFilter = "ALL" | "ACTIVE" | "LOCKED_SECURITY" | "SUSPENDED";
type ProtectedCredential = { privateLogin: string; credential: string };

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
}

function statusLabel(status: Account["status"]) {
  if (status === "ACTIVE") return "ATIVA";
  if (status === "LOCKED_SECURITY") return "BLOQUEADA";
  if (status === "SUSPENDED") return "SUSPENSA";
  return status;
}

function filterLabel(status: StatusFilter) {
  if (status === "ALL") return "STATUS";
  if (status === "ACTIVE") return "ATIVAS";
  if (status === "LOCKED_SECURITY") return "BLOQUEADAS";
  return "SUSPENSAS";
}

function accountLabel(account?: Account | null) {
  const name = String(account?.name || "").trim();
  if (name) return name;
  const shortId = String(account?.id || "").replace(/-/g, "").slice(0, 4).toUpperCase();
  const role = account?.role || "ACESSO";
  return `Acesso ${role}${shortId ? ` ${shortId}` : ""}`;
}

export function AccountsScreen({ session, onHome, onMenus, onAudit, onCritical }: {
  session: string;
  onHome: () => void;
  onMenus: () => void;
  onAudit: () => void;
  onCritical: () => void;
}) {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [mutationBusy, setMutationBusy] = useState(false);
  const [createModal, setCreateModal] = useState(false);
  const [displayName, setDisplayName] = useState("");
  const [login, setLogin] = useState("");
  const [role, setRole] = useState<AccountRole>("ADM");
  const [query, setQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState<RoleFilter>("ALL");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("ALL");
  const [protectedCredential, setProtectedCredential] = useState<ProtectedCredential | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Account | null>(null);
  const [rotateTarget, setRotateTarget] = useState<Account | null>(null);
  const [revealTarget, setRevealTarget] = useState<Account | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<Account | null>(null);
  const [detailTarget, setDetailTarget] = useState<Account | null>(null);
  const [securityTarget, setSecurityTarget] = useState<Account | null>(null);
  const [sessions, setSessions] = useState<AccountSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const refreshVersion = useRef(0);
  const mounted = useRef(true);
  const mutationLock = useRef(false);

  function beginMutation() {
    if (mutationLock.current) return false;
    mutationLock.current = true;
    setMutationBusy(true);
    return true;
  }

  function endMutation() {
    mutationLock.current = false;
    if (mounted.current) setMutationBusy(false);
  }

  async function refresh() {
    const version = ++refreshVersion.current;
    setLoading(true);
    try {
      const result = await listAccounts(session, {
        q: query || undefined,
        role: roleFilter === "ALL" ? undefined : roleFilter,
        status: statusFilter === "ALL" ? undefined : statusFilter
      });
      if (!mounted.current || version !== refreshVersion.current) return;
      setAccounts(result.accounts);
      if (detailTarget) {
        const updated = result.accounts.find((item) => item.id === detailTarget.id);
        if (updated) setDetailTarget(updated);
      }
      if (securityTarget) {
        const updated = result.accounts.find((item) => item.id === securityTarget.id);
        if (updated) setSecurityTarget(updated);
      }
    } catch (error) {
      if (mounted.current && version === refreshVersion.current) {
        Alert.alert("Falha ao carregar", error instanceof Error ? error.message : "Erro desconhecido");
      }
    } finally {
      if (mounted.current && version === refreshVersion.current) setLoading(false);
    }
  }

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      mutationLock.current = true;
      refreshVersion.current += 1;
    };
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => refresh().catch(() => {}), 250);
    return () => {
      clearTimeout(timer);
      refreshVersion.current += 1;
    };
  }, [session, query, roleFilter, statusFilter]);

  async function create() {
    if (!beginMutation()) return;
    try {
      const result = await createAccount(session, displayName.trim(), login.trim(), role);
      if (!mounted.current) return;
      setProtectedCredential({ privateLogin: result.privateLogin, credential: result.credential });
      setDisplayName("");
      setLogin("");
      setCreateModal(false);
      await refresh();
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Não foi possível criar", error instanceof Error ? error.message : "Erro desconhecido");
      }
    } finally {
      endMutation();
    }
  }

  async function suspendAccount(account: Account) {
    if (!beginMutation()) return;
    try {
      await setAccountState(session, account.id, "suspend");
      await refresh();
      if (detailTarget?.id === account.id) await reloadSessions(account, { useMutationLock: false });
    } catch (error) {
      if (mounted.current) Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      endMutation();
    }
  }

  function stateAction(account: Account) {
    if (mutationLock.current) return;
    if (account.status === "LOCKED_SECURITY") {
      setSecurityTarget(account);
      return;
    }
    if (account.status === "SUSPENDED") {
      setRestoreTarget(account);
      return;
    }

    Alert.alert(
      "Suspender acesso?",
      `Suspender ${accountLabel(account)} bloqueará novos logins e encerrará as sessões atuais dessa conta. Os arquivos e dados salvos não serão apagados.`,
      [
        { text: "Cancelar", style: "cancel" },
        { text: "Suspender", style: "destructive", onPress: () => suspendAccount(account).catch(() => {}) }
      ]
    );
  }

  async function openDetails(account: Account) {
    if (mutationLock.current) return;
    setDetailTarget(account);
    setSessionsLoading(true);
    try {
      setSessions((await listAccountSessions(session, account.id)).sessions);
    } catch (error) {
      setSessions([]);
      Alert.alert("Sessões indisponíveis", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      if (mounted.current) setSessionsLoading(false);
    }
  }

  async function reloadSessions(account: Account, { useMutationLock = false }: { useMutationLock?: boolean } = {}) {
    if (useMutationLock && !beginMutation()) return;
    setSessionsLoading(true);
    try {
      setSessions((await listAccountSessions(session, account.id)).sessions);
      await refresh();
    } catch (error) {
      if (mounted.current) Alert.alert("Sessões indisponíveis", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      if (mounted.current) setSessionsLoading(false);
      if (useMutationLock) endMutation();
    }
  }

  function confirmRevokeSession(account: Account, app1Session: AccountSession) {
    if (mutationLock.current) return;
    Alert.alert(
      "Revogar esta sessão?",
      `A sessão de ${app1Session.device_label || "este dispositivo"} será encerrada imediatamente. Isso não apaga a conta nem os arquivos.`,
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Revogar",
          style: "destructive",
          onPress: async () => {
            if (!beginMutation()) return;
            try {
              await revokeAccountSession(session, account.id, app1Session.id);
              await reloadSessions(account, { useMutationLock: false });
            } catch (error) {
              if (mounted.current) Alert.alert("Não foi possível revogar", error instanceof Error ? error.message : "Erro desconhecido");
            } finally {
              endMutation();
            }
          }
        }
      ]
    );
  }

  function confirmRevokeAllSessions(account: Account) {
    if (mutationLock.current) return;
    const activeCount = sessions.filter((item) => item.active).length;
    Alert.alert(
      "Revogar todas as sessões?",
      activeCount > 0
        ? `${activeCount} sessão(ões) ativa(s) de ${accountLabel(account)} serão encerradas. A conta continuará liberada para um novo login autorizado.`
        : `Não há sessões ativas visíveis para ${accountLabel(account)}. O servidor fará uma verificação final antes de concluir.`,
      [
        { text: "Cancelar", style: "cancel" },
        {
          text: "Revogar todas",
          style: "destructive",
          onPress: async () => {
            if (!beginMutation()) return;
            try {
              const result = await revokeAllAccountSessions(session, account.id);
              await reloadSessions(account, { useMutationLock: false });
              if (mounted.current) Alert.alert("Sessões revogadas", `${result.revokedCount} sessão(ões) encerrada(s).`);
            } catch (error) {
              if (mounted.current) Alert.alert("Não foi possível revogar", error instanceof Error ? error.message : "Erro desconhecido");
            } finally {
              endMutation();
            }
          }
        }
      ]
    );
  }

  async function securityChanged() {
    await refresh();
    if (detailTarget) await reloadSessions(detailTarget);
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <View style={styles.screenBody}>
          <Header title="CONTAS" onBack={onHome} />
          <View style={styles.listHeaderCompact}>
            <View style={{ flex: 1 }}>
              <Text style={styles.screenTitle}>Acessos do App 1</Text>
              <Text style={styles.muted}>Cada acesso mostra apenas o nome escolhido. Login privado e chave ficam ocultos e exigem confirmação DEV.</Text>
            </View>
            <Pressable disabled={mutationBusy} style={[styles.addButton, mutationBusy && styles.buttonMuted]} onPress={() => setCreateModal(true)}><Text style={styles.add}>＋</Text></Pressable>
          </View>

          <TextInput
            value={query}
            onChangeText={setQuery}
            editable={!mutationBusy}
            style={styles.searchInput}
            placeholder="Buscar nome do acesso..."
            placeholderTextColor="#6D6D73"
            autoCapitalize="none"
            autoCorrect={false}
          />

          <ScrollView style={styles.filterScroll} horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
            {(["ALL", "ADM", "DEV"] as RoleFilter[]).map((item) => (
              <Pressable disabled={mutationBusy} key={item} style={[styles.filterChip, roleFilter === item && styles.filterChipActive, item === "DEV" && roleFilter === item && styles.filterChipDev]} onPress={() => setRoleFilter(item)}>
                <Text style={[styles.filterChipText, roleFilter === item && styles.filterChipTextActive]}>{item === "ALL" ? "TODOS" : item}</Text>
              </Pressable>
            ))}
            <View style={styles.filterDivider} />
            {(["ALL", "ACTIVE", "LOCKED_SECURITY", "SUSPENDED"] as StatusFilter[]).map((item) => (
              <Pressable disabled={mutationBusy} key={`status-${item}`} style={[styles.filterChip, statusFilter === item && styles.filterChipActive]} onPress={() => setStatusFilter(item)}>
                <Text style={[styles.filterChipText, statusFilter === item && styles.filterChipTextActive]}>{filterLabel(item)}</Text>
              </Pressable>
            ))}
          </ScrollView>

          {loading ? <ActivityIndicator style={{ marginTop: 30 }} /> : (
            <FlatList
              data={accounts}
              keyExtractor={(item) => item.id}
              contentContainerStyle={styles.accountList}
              ListEmptyComponent={<Text style={styles.empty}>Nenhuma conta encontrada.</Text>}
              renderItem={({ item }) => (
                <View style={[styles.accountCard, item.status === "LOCKED_SECURITY" && { borderColor: "#5A2025", backgroundColor: "#100708" }, mutationBusy && styles.buttonMuted]}>
                  <Pressable disabled={mutationBusy} style={styles.accountTop} onPress={() => openDetails(item)}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={styles.cardTitle}>{accountLabel(item)}</Text>
                        <Text style={[styles.badge, item.role === "DEV" && styles.badgeDev]}>{item.role}</Text>
                      </View>
                      <Text style={styles.accountMeta}>{item.active_sessions || 0} sessão(ões) ativa(s) • atualizado {formatDate(item.updated_at)}</Text>
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : item.status === "LOCKED_SECURITY" ? { color: "#FF5148", fontSize: 10, fontWeight: "900" } : styles.suspended}>
                      {statusLabel(item.status)}
                    </Text>
                  </Pressable>

                  <View style={styles.rowGap}>
                    <Pressable disabled={mutationBusy} style={[styles.smallAction, item.status === "LOCKED_SECURITY" && { borderColor: "#5A2025", backgroundColor: "#150809" }]} onPress={() => setSecurityTarget(item)}>
                      <Text style={[styles.smallActionText, item.status === "LOCKED_SECURITY" && { color: "#FF5A52" }]}>SEGURANÇA</Text>
                    </Pressable>
                    <Pressable disabled={mutationBusy} style={styles.smallAction} onPress={() => stateAction(item)}>
                      <Text style={styles.smallActionText}>{item.status === "ACTIVE" ? "SUSPENDER" : item.status === "SUSPENDED" ? "LIBERAR • DEV" : "DESBLOQUEAR"}</Text>
                    </Pressable>
                    <Pressable disabled={mutationBusy} style={styles.smallAction} onPress={() => setRevealTarget(item)}>
                      <Text style={styles.smallActionText}>VER / COPIAR</Text>
                    </Pressable>
                    <Pressable disabled={mutationBusy} style={styles.smallAction} onPress={() => setRotateTarget(item)}>
                      <Text style={styles.smallActionText}>NOVA CHAVE</Text>
                    </Pressable>
                  </View>

                  <View style={styles.rowGap}>
                    <Pressable disabled={mutationBusy} style={[styles.smallAction, styles.smallDanger]} onPress={() => {
                      Alert.alert("Excluir conta", `Excluir ${accountLabel(item)}? A confirmação final exigirá uma credencial DEV ativa.`, [
                        { text: "Cancelar", style: "cancel" },
                        { text: "Continuar", style: "destructive", onPress: () => setDeleteTarget(item) }
                      ]);
                    }}>
                      <Text style={styles.smallDangerText}>EXCLUIR ACESSO DEFINITIVAMENTE</Text>
                    </Pressable>
                  </View>
                </View>
              )}
            />
          )}
        </View>
        <BottomNav current="accounts" onHome={onHome} onAccounts={() => {}} onMenus={onMenus} onAudit={onAudit} onCritical={onCritical} />
      </View>

      <Modal visible={createModal} transparent animationType="fade" onRequestClose={() => !mutationBusy && setCreateModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Criar acesso do App 1</Text>
            <Text style={styles.muted}>Primeiro escolha o nome que ficará visível no Keymaster. O login real fica privado depois da criação.</Text>
            <TextInput
              value={displayName}
              onChangeText={setDisplayName}
              editable={!mutationBusy}
              style={styles.input}
              placeholder="Nome do acesso (visível no Keymaster)"
              placeholderTextColor="#666"
              autoCorrect={false}
            />
            <TextInput
              value={login}
              onChangeText={setLogin}
              editable={!mutationBusy}
              style={styles.input}
              placeholder="Login privado"
              placeholderTextColor="#666"
              autoCapitalize="none"
              autoCorrect={false}
            />
            <View style={styles.rowGap}>
              <Pressable disabled={mutationBusy} style={[styles.halfButton, role === "ADM" && styles.selected]} onPress={() => setRole("ADM")}><Text style={styles.halfButtonText}>ADM</Text></Pressable>
              <Pressable disabled={mutationBusy} style={[styles.halfButton, role === "DEV" && styles.selectedDev]} onPress={() => setRole("DEV")}><Text style={styles.halfButtonText}>DEV</Text></Pressable>
            </View>
            <Button title={mutationBusy ? "CRIANDO..." : "CRIAR E GERAR CHAVE"} onPress={create} disabled={mutationBusy || displayName.trim().length < 2 || login.trim().length < 2} />
            <Button title="FECHAR" onPress={() => setCreateModal(false)} secondary disabled={mutationBusy} />
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(detailTarget)} transparent animationType="slide" onRequestClose={() => !mutationBusy && setDetailTarget(null)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalBox, styles.detailModal]}>
            {detailTarget ? (
              <>
                <View style={styles.detailHeader}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.cardTitle}>{accountLabel(detailTarget)}</Text>
                    <Text style={[styles.badge, detailTarget.role === "DEV" && styles.badgeDev]}>{detailTarget.role} • {statusLabel(detailTarget.status)}</Text>
                  </View>
                  <Pressable disabled={mutationBusy} onPress={() => setDetailTarget(null)}><Text style={styles.closeText}>✕</Text></Pressable>
                </View>
                <View style={styles.detailGrid}>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>CRIADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.created_at)}</Text></View>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>ATUALIZADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.updated_at)}</Text></View>
                </View>

                <Button title="VER / COPIAR LOGIN E CHAVE" disabled={mutationBusy} onPress={() => setRevealTarget(detailTarget)} />
                <Button title="GERAR NOVA CHAVE • CONFIRMAÇÃO DEV" disabled={mutationBusy} onPress={() => setRotateTarget(detailTarget)} secondary />
                <Button title="SEGURANÇA • DISPOSITIVOS • TENTATIVAS" disabled={mutationBusy} onPress={() => setSecurityTarget(detailTarget)} danger={detailTarget.status === "LOCKED_SECURITY"} />

                <View style={styles.detailSectionRow}>
                  <Text style={styles.sectionInline}>SESSÕES DO APP 1</Text>
                  <Pressable disabled={sessionsLoading || mutationBusy} onPress={() => reloadSessions(detailTarget, { useMutationLock: true })}><Text style={styles.refreshLink}>ATUALIZAR</Text></Pressable>
                </View>
                {sessionsLoading ? <ActivityIndicator style={{ marginVertical: 22 }} /> : (
                  <ScrollView style={styles.sessionsList}>
                    {sessions.length === 0 ? <Text style={styles.emptyCompact}>Nenhuma sessão registrada.</Text> : sessions.map((item) => (
                      <View key={item.id} style={styles.sessionCard}>
                        <View style={{ flex: 1 }}>
                          <Text style={styles.sessionTitle}>{item.device_label || "Dispositivo sem nome"}</Text>
                          <Text style={styles.accountMeta}>Criada {formatDate(item.created_at)} • expira {formatDate(item.expires_at)}</Text>
                        </View>
                        <Text style={item.active ? styles.active : styles.sessionOff}>{item.active ? "ATIVA" : item.revoked_at ? "REVOGADA" : "EXPIRADA"}</Text>
                        {item.active ? (
                          <Pressable disabled={mutationBusy} style={[styles.revokeButton, mutationBusy && styles.buttonMuted]} onPress={() => confirmRevokeSession(detailTarget, item)}>
                            <Text style={styles.revokeButtonText}>REVOGAR</Text>
                          </Pressable>
                        ) : null}
                      </View>
                    ))}
                  </ScrollView>
                )}
                <Button title={mutationBusy ? "AGUARDE..." : "REVOGAR TODAS AS SESSÕES"} danger disabled={mutationBusy} onPress={() => confirmRevokeAllSessions(detailTarget)} />
              </>
            ) : null}
          </View>
        </View>
      </Modal>

      <AccountCredentialModal value={protectedCredential} onClose={() => setProtectedCredential(null)} />

      <AccountSecurityModal
        visible={Boolean(securityTarget)}
        session={session}
        account={securityTarget}
        onClose={() => setSecurityTarget(null)}
        onChanged={securityChanged}
      />

      <DevAuthorizationModal
        visible={Boolean(restoreTarget)}
        session={session}
        action="RESTORE_APP1_ACCOUNT"
        targetId={restoreTarget?.id}
        title={restoreTarget ? `Liberar novamente ${accountLabel(restoreTarget)}` : "Liberar conta"}
        onCancel={() => setRestoreTarget(null)}
        onAuthorized={async (authorizationToken) => {
          const target = restoreTarget;
          if (!target || !beginMutation()) return;
          try {
            await setAccountState(session, target.id, "restore", authorizationToken);
            setRestoreTarget(null);
            await refresh();
            if (detailTarget?.id === target.id) await reloadSessions(target, { useMutationLock: false });
            if (mounted.current) Alert.alert("Acesso liberado", `${accountLabel(target)} pode autenticar novamente em um dispositivo autorizado.`);
          } finally {
            endMutation();
          }
        }}
      />

      <DevAuthorizationModal
        visible={Boolean(revealTarget)}
        session={session}
        action="REVEAL_APP1_CREDENTIAL"
        targetId={revealTarget?.id}
        title={revealTarget ? `Visualizar ${accountLabel(revealTarget)}` : "Visualizar acesso"}
        onCancel={() => setRevealTarget(null)}
        onAuthorized={async (authorizationToken) => {
          if (!revealTarget) return;
          try {
            const result = await revealAccountCredential(session, revealTarget.id, authorizationToken);
            setProtectedCredential({ privateLogin: result.privateLogin, credential: result.credential });
          } catch (error) {
            Alert.alert("Chave indisponível", error instanceof Error ? error.message : "Não foi possível visualizar esta chave.");
          } finally {
            setRevealTarget(null);
          }
        }}
      />

      <DevAuthorizationModal
        visible={Boolean(rotateTarget)}
        session={session}
        action="ROTATE_APP1_CREDENTIAL"
        targetId={rotateTarget?.id}
        title={rotateTarget ? `Gerar nova chave para ${accountLabel(rotateTarget)}` : "Gerar nova chave"}
        onCancel={() => setRotateTarget(null)}
        onAuthorized={async (authorizationToken) => {
          if (!rotateTarget) return;
          try {
            const result = await rotateCredential(session, rotateTarget.id, authorizationToken);
            setProtectedCredential({ privateLogin: result.privateLogin, credential: result.credential });
            await refresh();
            if (detailTarget?.id === rotateTarget.id) await reloadSessions(detailTarget);
          } catch (error) {
            Alert.alert("Não foi possível gerar", error instanceof Error ? error.message : "O servidor recusou a operação.");
          } finally {
            setRotateTarget(null);
          }
        }}
      />

      <DevAuthorizationModal
        visible={Boolean(deleteTarget)}
        session={session}
        action="DELETE_APP1_ACCOUNT"
        targetId={deleteTarget?.id}
        title={deleteTarget ? `Excluir ${accountLabel(deleteTarget)}` : "Excluir conta"}
        onCancel={() => setDeleteTarget(null)}
        onAuthorized={async (authorizationToken) => {
          if (!deleteTarget) return;
          await deleteAccount(session, deleteTarget.id, authorizationToken);
          setDeleteTarget(null);
          if (detailTarget?.id === deleteTarget.id) setDetailTarget(null);
          if (securityTarget?.id === deleteTarget.id) setSecurityTarget(null);
          await refresh();
        }}
      />
    </SafeAreaView>
  );
}
