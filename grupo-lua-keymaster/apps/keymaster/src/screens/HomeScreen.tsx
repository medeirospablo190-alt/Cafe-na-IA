import { useEffect, useState } from "react";
import { Pressable, SafeAreaView, ScrollView, Text, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { getDashboard, listManagedMenus, type Dashboard } from "../api";
import { BottomNav } from "../components/BottomNav";
import { Header } from "../components/Common";
import { styles } from "../styles";

type MenuSummary = {
  total: number;
  active: number;
  free: number;
  vip: number;
};

export function HomeScreen({ session, onAccounts, onMenus, onAudit, onCritical, onLogout }: {
  session: string;
  onAccounts: () => void;
  onMenus: () => void;
  onAudit: () => void;
  onCritical: () => void;
  onLogout: () => void;
}) {
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [menuSummary, setMenuSummary] = useState<MenuSummary | null>(null);

  useEffect(() => {
    let mounted = true;

    getDashboard(session)
      .then((result) => { if (mounted) setDashboard(result.dashboard); })
      .catch(() => { if (mounted) setDashboard(null); });

    listManagedMenus(session)
      .then((result) => {
        if (!mounted) return;
        setMenuSummary({
          total: result.menus.length,
          active: result.menus.filter((menu) => menu.status === "ACTIVE").length,
          free: result.menus.reduce((sum, menu) => sum + Number(menu.free_keys || 0), 0),
          vip: result.menus.reduce((sum, menu) => sum + Number(menu.vip_keys || 0), 0)
        });
      })
      .catch(() => { if (mounted) setMenuSummary(null); });

    return () => { mounted = false; };
  }, [session]);

  const maintenance = dashboard?.app1Maintenance;
  const totalKeys = menuSummary ? menuSummary.free + menuSummary.vip : null;
  const systemLabel = dashboard == null
    ? "VERIFICANDO"
    : maintenance
      ? "MANUTENÇÃO"
      : "ONLINE";

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.screenShell}>
        <ScrollView contentContainerStyle={styles.pageWithNav}>
          <Header title="KEYMASTER" onLogout={onLogout} />

          <View style={[styles.securityCard, maintenance && styles.criticalSecurity]}>
            <View style={styles.accountTop}>
              <View style={{ flex: 1 }}>
                <Text style={styles.eyebrow}>GRUPO LUA • ROOT ACCESS</Text>
                <Text style={[styles.cardTitle, { marginTop: 6 }]}>Controle central do App 1</Text>
              </View>
              <View style={styles.statusLine}>
                <View style={maintenance ? styles.redDot : styles.greenDot} />
                <Text style={maintenance ? styles.redText : styles.greenText}>{systemLabel}</Text>
              </View>
            </View>
            <Text style={styles.small}>
              {dashboard == null ? "Confirmando o estado do servidor..." : maintenance ? "Novos acessos do App 1 estão temporariamente bloqueados." : "Servidor disponível e sessão administrativa protegida."}
            </Text>
          </View>

          <View style={styles.metricGrid}>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>CONTAS</Text>
              <Text style={styles.metricValue}>{dashboard?.accounts.total ?? "—"}</Text>
              <Text style={styles.metricHint}>{dashboard ? `${dashboard.accounts.dev} DEV • ${dashboard.accounts.adm} ADM` : "carregando"}</Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>MENUS</Text>
              <Text style={styles.metricValue}>{menuSummary?.total ?? "—"}</Text>
              <Text style={styles.metricHint}>{menuSummary ? `${menuSummary.active} ativos` : "carregando"}</Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>CHAVES</Text>
              <Text style={styles.metricValue}>{totalKeys ?? "—"}</Text>
              <Text style={styles.metricHint}>{menuSummary ? `${menuSummary.free} FREE • ${menuSummary.vip} VIP` : "carregando"}</Text>
            </View>
            <View style={styles.metricCard}>
              <Text style={styles.metricLabel}>SESSÕES</Text>
              <Text style={styles.metricValue}>{dashboard?.activeSessions ?? "—"}</Text>
              <Text style={styles.metricHint}>App 1 ativas</Text>
            </View>
          </View>

          <Text style={styles.small}>{dashboard ? `${dashboard.auditEvents24h} eventos de auditoria nas últimas 24h` : "Carregando auditoria..."}</Text>

          <Text style={styles.section}>ATALHOS</Text>
          <Pressable style={styles.featureCard} onPress={onAccounts}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>♙</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Contas e dispositivos</Text>
              <Text style={styles.muted}>Acessos, sessões e segurança.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Pressable style={styles.featureCard} onPress={onMenus}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>⌘</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Menus e chaves</Text>
              <Text style={styles.muted}>Menus, URLs e autorizações FREE/VIP.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Pressable style={styles.featureCard} onPress={onAudit}>
            <View style={styles.featureIcon}><Text style={styles.featureIconText}>≣</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Auditoria</Text>
              <Text style={styles.muted}>Eventos administrativos do servidor.</Text>
            </View>
            <Text style={styles.cardArrow}>›</Text>
          </Pressable>

          <Pressable style={[styles.featureCard, styles.criticalCard]} onPress={onCritical}>
            <View style={[styles.featureIcon, styles.featureIconDanger]}><Text style={[styles.featureIconText, styles.redText]}>!</Text></View>
            <View style={{ flex: 1 }}>
              <Text style={styles.cardTitle}>Área DEV protegida</Text>
              <Text style={styles.muted}>Manutenção e reinício com reautenticação DEV.</Text>
            </View>
            <Text style={[styles.cardArrow, styles.redText]}>›</Text>
          </Pressable>
        </ScrollView>
        <BottomNav current="home" onHome={() => {}} onAccounts={onAccounts} onMenus={onMenus} onAudit={onAudit} onCritical={onCritical} />
      </View>
    </SafeAreaView>
  );
}
