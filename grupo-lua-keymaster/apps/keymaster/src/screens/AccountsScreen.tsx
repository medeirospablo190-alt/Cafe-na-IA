import { useEffect, useState } from "react";
import { ActivityIndicator, Alert, FlatList, Modal, Pressable, SafeAreaView, Text, TextInput, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { type Account, type AccountRole, createAccount, deleteAccount, listAccounts, rotateCredential, setAccountState } from "../api";
import { Button, Header } from "../components/Common";
import { CredentialModal } from "../components/CredentialModal";
import { DevAuthorizationModal } from "../components/DevAuthorizationModal";
import { styles } from "../styles";

export function AccountsScreen({ session, onBack }: { session: string; onBack: () => void }) {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(false);
  const [login, setLogin] = useState("");
  const [role, setRole] = useState<AccountRole>("ADM");
  const [revealedCredential, setRevealedCredential] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Account | null>(null);

  async function refresh() {
    setLoading(true);
    try {
      setAccounts((await listAccounts(session)).accounts);
    } catch (error) {
      Alert.alert("Falha ao carregar", error instanceof Error ? error.message : "Erro desconhecido");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { refresh().catch(() => {}); }, [session]);

  async function create() {
    try {
      const result = await createAccount(session, login, role);
      setRevealedCredential(result.credential);
      setLogin("");
      setModal(false);
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

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.pageFlex}>
        <Header title="ACESSOS" onBack={onBack} />
        <View style={styles.listHeader}>
          <View>
            <Text style={styles.screenTitle}>Contas do App 1</Text>
            <Text style={styles.muted}>Somente ADM e DEV. Credenciais novas aparecem uma única vez.</Text>
          </View>
          <Pressable style={styles.addButton} onPress={() => setModal(true)}><Text style={styles.add}>＋</Text></Pressable>
        </View>

        {loading ? <ActivityIndicator style={{ marginTop: 30 }} /> : (
          <FlatList
            data={accounts}
            keyExtractor={(item) => item.id}
            contentContainerStyle={{ paddingTop: 18, paddingBottom: 40 }}
            ListEmptyComponent={<Text style={styles.empty}>Nenhuma conta criada.</Text>}
            renderItem={({ item }) => (
              <View style={styles.accountCard}>
                <View style={styles.accountTop}>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.cardTitle}>{item.login}</Text>
                    <Text style={[styles.badge, item.role === "DEV" && styles.badgeDev]}>{item.role}</Text>
                  </View>
                  <Text style={item.status === "ACTIVE" ? styles.active : styles.suspended}>{item.status}</Text>
                </View>
                <View style={styles.rowGap}>
                  <Pressable style={styles.smallAction} onPress={() => action(item, item.status === "ACTIVE" ? "suspend" : "restore")}>
                    <Text style={styles.smallActionText}>{item.status === "ACTIVE" ? "SUSPENDER" : "LIBERAR"}</Text>
                  </Pressable>
                  <Pressable style={styles.smallAction} onPress={() => action(item, "rotate")}>
                    <Text style={styles.smallActionText}>NOVA CHAVE</Text>
                  </Pressable>
                  <Pressable style={[styles.smallAction, styles.smallDanger]} onPress={() => {
                    Alert.alert(
                      "Excluir conta",
                      `Excluir ${item.login}? A confirmação final exigirá uma credencial DEV ativa.`,
                      [
                        { text: "Cancelar", style: "cancel" },
                        { text: "Continuar", style: "destructive", onPress: () => setDeleteTarget(item) }
                      ]
                    );
                  }}>
                    <Text style={styles.smallDangerText}>EXCLUIR</Text>
                  </Pressable>
                </View>
              </View>
            )}
          />
        )}
      </View>

      <Modal visible={modal} transparent animationType="fade" onRequestClose={() => setModal(false)}>
        <View style={styles.modalBackdrop}>
          <View style={styles.modalBox}>
            <Text style={styles.cardTitle}>Criar acesso do App 1</Text>
            <TextInput value={login} onChangeText={setLogin} style={styles.input} placeholder="Login administrativo" placeholderTextColor="#666" />
            <View style={styles.rowGap}>
              <Pressable style={[styles.halfButton, role === "ADM" && styles.selected]} onPress={() => setRole("ADM")}><Text style={styles.halfButtonText}>ADM</Text></Pressable>
              <Pressable style={[styles.halfButton, role === "DEV" && styles.selectedDev]} onPress={() => setRole("DEV")}><Text style={styles.halfButtonText}>DEV</Text></Pressable>
            </View>
            <Button title="CRIAR E GERAR CHAVE" onPress={create} disabled={login.trim().length < 2} />
            <Button title="FECHAR" onPress={() => setModal(false)} secondary />
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
