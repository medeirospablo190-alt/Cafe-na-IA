import { Pressable, Text, View } from "react-native";
import { styles } from "../styles";

export type NavKey = "home" | "accounts" | "menus" | "audit" | "critical";

export function BottomNav({ current, onHome, onAccounts, onMenus, onAudit, onCritical }: {
  current: NavKey;
  onHome: () => void;
  onAccounts: () => void;
  onMenus: () => void;
  onAudit: () => void;
  onCritical: () => void;
}) {
  const items: Array<{ key: NavKey; icon: string; label: string; onPress: () => void }> = [
    { key: "home", icon: "⌂", label: "Início", onPress: onHome },
    { key: "accounts", icon: "♙", label: "Contas", onPress: onAccounts },
    { key: "menus", icon: "⌘", label: "Chaves", onPress: onMenus },
    { key: "audit", icon: "≣", label: "Auditoria", onPress: onAudit },
    { key: "critical", icon: "!", label: "Crítico", onPress: onCritical }
  ];

  return (
    <View style={styles.bottomNav}>
      {items.map((item) => {
        const active = current === item.key;
        return (
          <Pressable key={item.key} style={styles.bottomNavItem} onPress={item.onPress}>
            <View style={[
              styles.bottomNavIcon,
              active && styles.bottomNavIconActive,
              item.key === "critical" && active && styles.bottomNavIconDanger
            ]}>
              <Text style={[styles.bottomNavIconText, active && styles.bottomNavTextActive]}>{item.icon}</Text>
            </View>
            <Text style={[
              styles.bottomNavLabel,
              active && styles.bottomNavTextActive,
              item.key === "critical" && active && styles.redText
            ]}>{item.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}
