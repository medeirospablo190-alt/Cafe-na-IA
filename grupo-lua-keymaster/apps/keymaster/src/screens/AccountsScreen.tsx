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
  revokeAccountSession,
  revokeAllAccountSessions,
  rotateCredential,
  setAccountState
} from "../api";
import { BottomNav } from "../components/BottomNav";
import { Button, Header } from "../components/Common";
import { CredentialModal } from "../components/CredentialModal";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { styles } from "../styles";

type RoleFilter = "ALL" | AccountRole;
type StatusFilter = "ALL" | "ACTIVE" | "SUSPENDED";

function formatDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR");
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
  const [login, setLogin] = useState("");
  const [role, setRole] = useState<AccountRole>("ADM");
  const [query, setQuery] = useState("");
  const [roleFilter, setRoleFilter] = useState<RoleFilter>("ALL");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("ALL");
  const [revealedCredential, setRevealedCredential] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Account | null>(null);
  const [detailTarget, setDetailTarget] = useState<Account | null>(null);
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
      const result = await createAccount(session, login, role);
      setRevealedCredential(result.credential);
      setLogin("");
      setCreateModal(false);
      await refresh();
    } catch (error) {
      Alert.alert("Não foi possível criar", error instanceof Error ? error.message : "Erro desconhecido");
    }
  }

  async function action(account: Account, kind: "suspend" | "restore" | "rotate") {
    try {
      if (kind === "rotate") {
        const result = await rotateCredential(session, account.id);
        setRevealedCredential(result.credential);
      } else {
        await setAccountState(session, account.id, kind);
      }
      await refresh();
    } catch (error) {
      Alert.alert("Falha", error instanceof Error ? error.message : "Erro desconhecido");
    }
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

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <View style={styles.screenBody}>
          <Header title="CONTAS" onBack={onHome} />
          <View style={styles.listHeaderCompact}>
            <View style={{ flex: 1 }}>
              <Text style={styles.screenTitle}>Acessos do App 1</Text>
              <Text style={styles.muted}>ADM e DEV. Toque em uma conta para visualizar sessões e detalhes.</Text>
            </View>
            <Pressable style={styles.addButton} onPress={() => setCreateModal(true)}><Text style={styles.add}>＋</Text></Pressable>
          </View>

          <TextInput
            value={query}
            onChangeText={setQuery}
            style={styles.searchInput}
            placeholder="Buscar login..."
            placeholderTextColor="#6D6D73"
            autoCapitalize="none"
            autoCorrect={false}
          />

          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.filterRow}>
            {(["ALL", "ADM", "DEV"] as RoleFilter[]).map((item) => (
              <Pressable key={item} style={[styles.filterChip, roleFilter === item && styles.filterChipActive, item === "DEV" && roleFilter === item && styles.filterChipDev]} onPress={() => setRoleFilter(item)}>
                <Text style={[styles.filterChipText, roleFilter === item && styles.filterChipTextActive]}>{item === "ALL" ? "TODOS" : item}</Text>
              </Pressable>
            ))}
            <View style={styles.filterDivider} />
            {(["ALL", "ACTIVE", "SUSPENDED"] as StatusFilter[]).map((item) => (
              <Pressable key={`status-${item}`} style={[styles.filterChip, statusFilter === item && styles.filterChipActive]} onPress={() => setStatusFilter(item)}>
                <Text style={[styles.filterChipText, statusFilter === item && styles.filterChipTextActive]}>{item === "ALL" ? "STATUS" : item === "ACTIVE" ? "ATIVAS" : "SUSPENSAS"}</Text>
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
                <View style={styles.accountCard}>
                  <Pressable style={styles.accountTop} onPress={() => openDetails(item)}>
                    <View style={{ flex: 1 }}>
                      <View style={styles.accountTitleRow}>
                        <Text style={styles.cardTitle}>{item.login}</Text>
                        <Text style={[styles.badge, item.role === "DEV" && styles.badgeDev]}>{item.role}</Text>
                      </View>
                      <Text style={styles.accountMeta}>{item.active_sessions || 0} sessão(ões) ativa(s) • atualizado {formatDate(item.updated_at)}</Text>
                    </View>
                    <Text style={item.status === "ACTIVE" ? styles.active : styles.suspended}>{item.status === "ACTIVE" ? "ATIVA" : "SUSPENSA"}</Text>
                  </Pressable>
                  <View style={styles.rowGap}>
                    <Pressable style={styles.smallAction} onPress={() => action(item, item.status === "ACTIVE" ? "suspend" : "restore")}>
                      <Text style={styles.smallActionText}>{item.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"}</Text>
                    </Pressable>
                    <Pressable style={styles.smallAction} onPress={() => action(item, "rotate")}>
                      <Text style={styles.smallActionText}>NOVA CHAVE</Text>
                    </Pressable>
                    <Pressable style={[styles.smallAction, styles.smallDanger]} onPress={() => {
                      Alert.alert("Excluir conta", `Excluir ${item.login}? A confirmação final exigirá uma credencial DEV ativa.`, [
                        { text: "Cancelar", style: "cancel" },
                        { text: "Continuar", style: "destructive", onPress: () => setDeleteTarget(item) }
                      ]);
                    }}>
                      <Text style={styles.smallDangerText}>EXCLUIR</Text>
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
            <TextInput value={login} onChangeText={setLogin} style={styles.input} placeholder="Login administrativo" placeholderTextColor="#666" />
            <View style={styles.rowGap}>
              <Pressable style={[styles.halfButton, role === "ADM" && styles.selected]} onPress={() => setRole("ADM")}><Text style={styles.halfButtonText}>ADM</Text></Pressable>
              <Pressable style={[styles.halfButton, role === "DEV" && styles.selectedDev]} onPress={() => setRole("DEV")}><Text style={styles.halfButtonText}>DEV</Text></Pressable>
            </View>
            <Button title="CRIAR E GERAR CHAVE" onPress={create} disabled={login.trim().length < 2} />
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
                    <Text style={styles.cardTitle}>{detailTarget.login}</Text>
                    <Text style={[styles.badge, detailTarget.role === "DEV" && styles.badgeDev]}>{detailTarget.role} • {detailTarget.status}</Text>
                  </View>
                  <Pressable onPress={() => setDetailTarget(null)}><Text style={styles.closeText}>✕</Text></Pressable>
                </View>
                <View style={styles.detailGrid}>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>CRIADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.created_at)}</Text></View>
                  <View style={styles.detailCell}><Text style={styles.detailLabel}>ATUALIZADA</Text><Text style={styles.detailValue}>{formatDate(detailTarget.updated_at)}</Text></View>
                </View>
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

      <CredentialModal credential={revealedCredential} onClose={() => setRevealedCredential(null)} />
      <DevAuthorizationModal
        visible={Boolean(deleteTarget)}
        session={session}
        action="DELETE_APP1_ACCOUNT"
        targetId={deleteTarget?.id}
        title={deleteTarget ? `Excluir ${deleteTarget.login}` : "Excluir conta"}
        onCancel={() => setDeleteTarget(null)}
        onAuthorized={async (authorizationToken) => {
          if (!deleteTarget) return;
          await deleteAccount(session, deleteTarget.id, authorizationToken);
          setDeleteTarget(null);
          await refresh();
        }}
      />
    </SafeAreaView>
  );
}
