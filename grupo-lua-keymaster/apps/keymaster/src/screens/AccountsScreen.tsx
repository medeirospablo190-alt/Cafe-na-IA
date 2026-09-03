import { useEffect, useState } from "react";
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

export function AccountsScreen({ session, onHome, onMenus, onAudit, onCritical }: {
  session: string;
  onHome: () => void;
  onMenus: () => void;
  onAudit: () => void;
  onCritical: () => void;
}) {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
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
  const [detailTarget, setDetailTarget] = useState<Account | null>(null);
  const [securityTarget, setSecurityTarget] = useState<Account | null>(null);
  const [sessions, setSessions] = useState<AccountSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);

  async function refresh() {
    setLoading(true);
    try {
      const result = await listAccounts(session, {
        q: query || undefined,
        role: roleFilter === "ALL" ? undefined : roleFilter,
        status: statusFilter === "ALL" ? undefined : statusFilter
      });
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
      Alert.alert("Falha ao carregar", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => refresh().catch(() => {}), 250);
    return () => clearTimeout(timer);
  }, [session, query, roleFilter, statusFilter]);

  async function create() {
    try {
      const result = await createAccount(session, displayName.trim(), login.trim(), role);
      setProtectedCredential({ privateLogin: result.privateLogin, credential: result.credential });
      setDisplayName("");
      setLogin("");
      setCreateModal(false);
      await refresh();
    } catch (error) {
      Alert.alert("Não foi possível criar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function stateActionRequest(account: Account, kind: "suspend" | "restore") {
    try {
      await setAccountState(session, account.id, kind);
      await refresh();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  function stateAction(account: Account) {
    if (account.status === "LOCKED_SECURITY") {
      setSecurityTarget(account);
      return;
    }
    stateActionRequest(account, account.status === "ACTIVE" ? "suspend" : "restore").catch(() => {});
  }

  async function openDetails(account: Account) {
    setDetailTarget(account);
    setSessionsLoading(true);
    try {
      setSessions((await listAccountSessions(session, account.id)).sessions);
    } catch (error) {
      setSessions([]);
      Alert.alert("Sessões indisponíveis", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setSessionsLoading(false);
    }
  }

  async function reloadSessions(account: Account) {
    setSessionsLoading(true);
    try {
      setSessions((await listAccountSessions(session, account.id)).sessions);
      await refresh();
    } finally {
      setSessionsLoading(false);
    }
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
              <Text style={styles.muted}>Os nomes abaixo são apenas rótulos. Login privado e chave ficam ocultos e exigem confirmação DEV.</Text>
            </View>
            <Pressable style={styles.addButton} onPress={() => setCreateModal(true)}><Text style={styles.add}>＋</Text></Pressable>
          </View>

          <TextInput
            value={query}
            onChangeText={setQuery}
            style={styles.searchInput}
            placeholder="Buscar nome do acesso..."
            placeholderTextColor="#6D6D73"
            autoCapitalize="none"
            autoCorrect={false}
          />

          <ScrollView style={styles.filterScroll} horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
            {(["ALL", "ADM", "DEV"] as RoleFilter[]).map((item) => (
              <Pressable key={item} style={[styles.filterChip, roleFilter === item && styles.filterChipActive, item === "DEV" && roleFilter === item && styles.filterChipDev]} onPress={() => setRoleFilter(item)}>
                <Text style={[styles.filterChipText, roleFilter === item && styles.filterChipTextActive]}>{item === "ALL" ? "TODOS" : item}</Text>
              </Pressable>
            ))}
            <View style={styles.filterDivider} />
            {(["ALL", "ACTIVE", "LOCKED_SECURITY", "SUSPENDED"] as StatusFilter[]).map((item) => (
              <Pressable key={`status-${item}`} style={[styles.filterChip, statusFilter === item && styles.filterChipActive]} onPress={() => setStatusFilter(item)}>
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
                <View style={[styles.accountCard, item.status === "LOCKED_SECURITY" && { borderColor: "#5A2025", backgroundColor: "#100708" }]}>
                  <Pressable style={styles.accountTop} onPress={() => openDetails(item)}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={styles.cardTitle}>{item.name}</Text>
                        <Text style={[styles.badge, item.role === "DEV" && styles.badgeDev]}>{item.role}</Text>
                      </View>
                      <Text style={styles.accountMeta}>{item.active_sessions || 0} sessão(ões) ativa(s) • atualizado {formatDate(item.updated_at)}</Text>
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : item.status === "LOCKED_SECURITY" ? { color: "#FF5148", fontSize: 10, fontWeight: "900" } : styles.suspended}>
                      {statusLabel(item.status)}
                    </Text>
                  </Pressable>

                  <View style={styles.rowGap}>
                    <Pressable style={[styles.smallAction, item.status === "LOCKED_SECURITY" && { borderColor: "#5A2025", backgroundColor: "#150809" }]} onPress={() => setSecurityTarget(item)}>
                      <Text style={[styles.smallActionText, item.status === "LOCKED_SECURITY" && { color: "#FF5A52" }]}>SEGURANÇA</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => stateAction(item)}>
                      <Text style={styles.smallActionText}>{item.status === "ACTIVE" ? "SUSPENDER" : item.status === "SUSPENDED" ? "LIBERAR" : "DESBLOQUEAR"}</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => setRevealTarget(item)}>
                      <Text style={styles.smallActionText}>VER / COPIAR</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => setRotateTarget(item)}>
                      <Text style={styles.smallActionText}>NOVA CHAVE</Text>
                    </Pressable>
                  </View>

                  <View style={styles.rowGap}>
                    <Pressable style={[styles.smallAction, styles.smallDanger]} onPress={() => {
                      Alert.alert("Excluir conta", `Excluir ${item.name}? A confirmação final exigirá uma credencial DEV ativa.`, [
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

      <Modal visible={createModal} transparent animationType="fade" onRequestClose={() => setCreateModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Criar acesso do App 1</Text>
            <Text style={styles.muted}>Primeiro escolha o nome que ficará visível no Keymaster. O login real fica privado depois da criação.</Text>
            <TextInput
              value={displayName}
              onChangeText={setDisplayName}
              style={styles.input}
              placeholder="Nome do acesso (visível no Keymaster)"
              placeholderTextColor="#666"
              autoCorrect={false}
            />
            <TextInput
              value={login}
              onChangeText={setLogin}
              style={styles.input}
              placeholder="Login privado"
              placeholderTextColor="#666"
              autoCapitalize="none"
              autoCorrect={false}
            />
            <View style={styles.rowGap}>
              <Pressable style={[styles.halfButton, role === "ADM" && styles.selected]} onPress={() => setRole("ADM")}><Text style={styles.halfButtonText}>ADM</Text></Pressable>
              <Pressable style={[styles.halfButton, role === "DEV" && styles.selectedDev]} onPress={() => setRole("DEV")}><Text style={styles.halfButtonText}>DEV</Text></Pressable>
            </View>
            <Button title="CRIAR E GERAR CHAVE" onPress={create} disabled={displayName.trim().length < 2 || login.trim().length < 2} />
            <Button title="FECHAR" onPress={() => setCreateModal(false)} secondary />
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(detailTarget)} transparent animationType="slide" onRequestClose={() => setDetailTarget(null)}>
        <View style={styles.modalBackdrop}>
          <View style={[styles.modalBox, styles.detailModal]}>
            {detailTarget ? (
              <>
                <View style={styles.detailHeader}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.cardTitle}>{detailTarget.name}</Text>
                    <Text style={[styles.badge, detailTarget.role === "DEV" && styles.badgeDev]}>{detailTarget.role} • {statusLabel(detailTarget.status)}</Text>
                  </View>
                  <Pressable onPress={() => setDetailTarget(null)}><Text style={styles.closeText}>✕</Text></Pressable>
                </View>
                <View style={styles.detailGrid}>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>CRIADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.created_at)}</Text></View>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>ATUALIZADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.updated_at)}</Text></View>
                </View>

                <Button title="VER / COPIAR LOGIN E CHAVE" onPress={() => setRevealTarget(detailTarget)} />
                <Button title="GERAR NOVA CHAVE • CONFIRMAÇÃO DEV" onPress={() => setRotateTarget(detailTarget)} secondary />
                <Button title="SEGURANÇA • DISPOSITIVOS • TENTATIVAS" onPress={() => setSecurityTarget(detailTarget)} danger={detailTarget.status === "LOCKED_SECURITY"} />

                <View style={styles.detailSectionRow}>
                  <Text style={styles.sectionInline}>SESSÕES DO APP 1</Text>
                  <Pressable onPress={() => reloadSessions(detailTarget)}><Text style={styles.refreshLink}>ATUALIZAR</Text></Pressable>
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
                          <Pressable style={styles.revokeButton} onPress={async () => {
                            await revokeAccountSession(session, detailTarget.id, item.id);
                            await reloadSessions(detailTarget);
                          }}><Text style={styles.revokeButtonText}>REVOGAR</Text></Pressable>
                        ) : null}
                      </View>
                    ))}
                  </ScrollView>
                )}
                <Button title="REVOGAR TODAS AS SESSÕES" danger onPress={async () => {
                  const result = await revokeAllAccountSessions(session, detailTarget.id);
                  await reloadSessions(detailTarget);
                  Alert.alert("Sessões revogadas", `${result.revokedCount} sessão(ões) encerrada(s).`);
                }} />
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
        visible={Boolean(revealTarget)}
        session={session}
        action="REVEAL_APP1_CREDENTIAL"
        targetId={revealTarget?.id}
        title={revealTarget ? `Visualizar ${revealTarget.name}` : "Visualizar acesso"}
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
        title={rotateTarget ? `Gerar nova chave para ${rotateTarget.name}` : "Gerar nova chave"}
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
        title={deleteTarget ? `Excluir ${deleteTarget.name}` : "Excluir conta"}
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
