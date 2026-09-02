import { Pressable, Text, View } from "react-native";
import { styles } from "../styles";

export function Button({
  title,
  onPress,
  disabled,
  danger,
  secondary
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  danger?: boolean;
  secondary?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        secondary && styles.buttonSecondary,
        danger && styles.buttonDanger,
        (disabled || pressed) && styles.buttonMuted
      ]}
    >
      <Text style={[styles.buttonText, secondary && styles.buttonTextSecondary, danger && styles.buttonTextDanger]}>
        {title}
      </Text>
    </Pressable>
  );
}

export function Header({ title, onBack, onLogout }: { title: string; onBack?: () => void; onLogout?: () => void }) {
  return (
    <View style={styles.topRow}>
      <View style={styles.headerSide}>
        {onBack ? <Pressable onPress={onBack}><Text style={styles.link}>‹ Voltar</Text></Pressable> : null}
      </View>
      <View style={styles.headerCenter}>
        <Text style={styles.eyebrow}>GRUPO LUA</Text>
        <Text style={styles.headerTitle}>{title}</Text>
      </View>
      <View style={[styles.headerSide, styles.headerRight]}>
        {onLogout ? <Pressable onPress={onLogout}><Text style={styles.link}>Sair</Text></Pressable> : null}
      </View>
    </View>
  );
}
