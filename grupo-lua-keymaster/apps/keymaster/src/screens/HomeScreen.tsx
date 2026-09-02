import { useEffect, useState } from "react";
import { Pressable, SafeAreaView, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { API_URL } from "../config";
import { getDashboard, type Dashboard } from "../api";
import { BottomNav } from "../components/BottomNav";
import { Header } from "../components/Common";
import { styles } from "../styles";

export function HomeScreen({ session, onAccounts, onMenus, onAudit, onCritical, onLogout }: {
  session: string;
  onAccounts: () => void;
  onMenus: () => void;
  onAudit: () => void;
  onCritical: () => void;
  onLogout: () => void;
}) {
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);

  useEffect(() => {
    getDashboard(session).then((r) => setDashboard(r.dashboard)).catch(() => setDashboard(null));
  }, [session]);

  const maintenance = dashboard?.app1Maintenance;

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <ScrollView contentContainerStyle={styles.pageWithNav}>
          <Header title="KEYMASTER" onLogout={onLogout} />

          <View style={styles.heroCard}>
            <View style={styles.heroBadge}><Text style={styles.heroBadgeText}>ROOT ACCESS</Text></View>
            <Text style={styles.heroTitle}>GRUPO LUA</Text>
            <Text style={styles.heroSubtitle}>Painel de credenciais, menus e ações críticas</Text>
            <View style={styles.statusLine}>
              <View style={styles.greenDot} />
              <Text style={styles.securityTitle}>Sessão protegida e validada</Text>
            </View>
            <Text style={styles.small}>Servidor: {API_URL}</Text>
          </View>

          <View style={styles.metricGrid}>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>APP 1</Text>
              <Text style={[styles.metricValue, maintenance ? styles.redText : styles.greenText]}>
                {dashboard == null ? "—" : maintenance ? "MANUTENÇÃO" : "ONLINE"}
              </Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>CONTAS</Text>
              <Text style={styles.metricValue}>{dashboard?.accounts.total ?? "—"}</Text>
              <Text style={styles.metricHint}>{dashboard ? `${dashboard.accounts.dev} DEV • ${dashboard.accounts.adm} ADM` : "carregando"}</Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>SESSÕES</Text>
              <Text style={styles.metricValue}>{dashboard?.activeSessions ?? "—"}</Text>
              <Text style={styles.metricHint}>ativas agora</Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>AUDITORIA</Text>
              <Text style={styles.metricValue}>{dashboard?.auditEvents24h ?? "—"}</Text>
              <Text style={styles.metricHint}>eventos / 24h</Text>
            </View>
          </View>

          <Text style={styles.section}>ADMINISTRAÇÃO</Text>
          <Pressable style={styles.featureCard} onPress={onAccounts}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>♙</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Administradores e DEVs</Text>
              <Text style={styles.muted}>Buscar, filtrar, criar, suspender, rotacionar credenciais e controlar sessões.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Pressable style={styles.featureCard} onPress={onMenus}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>⌘</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Menus e chaves FREE/VIP</Text>
              <Text style={styles.muted}>Cadastrar fontes .lua, gerar URLs de acesso e administrar autorizações por menu.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Pressable style={styles.featureCard} onPress={onAudit}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>≣</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Auditoria do sistema</Text>
              <Text style={styles.muted}>Histórico server-side de logins, contas, sessões, menus e ações críticas.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Text style={styles.section}>AÇÕES CRÍTICAS</Text>
          <Pressable style={[styles.featureCard, styles.criticalCard]} onPress={onCritical}>
            <View style={[styles.featureIcon, styles.featureIconDanger]}><Text style={[styles.featureIconText, styles.redText]}>!</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Área DEV protegida</Text>
              <Text style={styles.muted}>Manutenção e reinício exigem reautenticação DEV e autorização de uso único.</Text>
              <Text style={styles.criticalLabel}>REAUTENTICAÇÃO OBRIGATÓRIA</Text>
            </View>
            <Text style={[styles.cardArrow, styles.redText]}>›</Text>
          </Pressable>
        </ScrollView>
        <BottomNav current="home" onHome={() => {}} onAccounts={onAccounts} onMenus={onMenus} onAudit={onAudit} onCritical={onCritical} />
      </View>
    </SafeAreaView>
  );
}
