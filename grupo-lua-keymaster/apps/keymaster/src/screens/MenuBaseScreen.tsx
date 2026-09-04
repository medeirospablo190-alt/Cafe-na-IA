import { useMemo, useState } from "react";
import { Alert, Pressable, SafeAreaView, ScrollView, Text, TextInput, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import * as Clipboard from "expo-clipboard";
import { Header } from "../components/Common";
import { styles } from "../styles";

const LOGIN_RAW_URL =
  "https://raw.githubusercontent.com/medeirospablo190-alt/Cafe-na-IA/main/GrupoLuaLogin.lua";

const LOGIN_IMAGE_ASSET = "rbxassetid://91124214069969";
const LOGIN_LAYOUT = "520 × 260";

function normalizeMenuId(value: string) {
  return value.trim();
}

function validMenuId(value: string) {
  return /^menu_[A-Za-z0-9_-]{6,80}$/.test(normalizeMenuId(value));
}

function buildLoader(menuId: string) {
  const id = normalizeMenuId(menuId);
  return [
    `getgenv().GRUPO_LUA_MENU_ID = ${JSON.stringify(id)}`,
    `loadstring(game:HttpGet(${JSON.stringify(LOGIN_RAW_URL)}))()`
  ].join("\n");
}

export function MenuBaseScreen({ onBack, onMenus }: {
  onBack: () => void;
  onMenus: () => void;
}) {
  const [menuId, setMenuId] = useState("");
  const normalized = normalizeMenuId(menuId);
  const isValid = validMenuId(normalized);
  const loader = useMemo(() => isValid ? buildLoader(normalized) : "", [normalized, isValid]);

  async function copyLoader() {
    if (!isValid || !loader) {
      Alert.alert("Menu ID inválido", "Use o ID público criado pelo Keymaster, começando por menu_.");
      return;
    }
    await Clipboard.setStringAsync(loader);
    Alert.alert("Loadstring copiado", "O loader deste menu foi copiado para a área de transferência.");
  }

  async function copyBaseUrl() {
    await Clipboard.setStringAsync(LOGIN_RAW_URL);
    Alert.alert("URL copiada", "A URL do login-base foi copiada.");
  }

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.pageWithNav} keyboardShouldPersistTaps="handled">
        <Header title="LOGIN-BASE" onBack={onBack} />

        <View style={styles.securityCard}>
          <Text style={styles.eyebrow}>GRUPO LUA • MODELO OFICIAL</Text>
          <Text style={[styles.cardTitle, { marginTop: 6 }]}>Login-base dos menus</Text>
          <Text style={styles.muted}>
            Todo menu cadastrado pode usar este mesmo login. O Keymaster muda apenas o menuId e mantém a chave FREE/VIP no servidor.
          </Text>
        </View>

        <Text style={styles.section}>BASE ATUAL</Text>
        <View style={styles.detailGrid}>
          <View style={styles.detailCell}>
            <Text style={styles.detailLabel}>LAYOUT</Text>
            <Text style={styles.detailValue}>{LOGIN_LAYOUT}</Text>
          </View>
          <View style={styles.detailCell}>
            <Text style={styles.detailLabel}>IMAGEM</Text>
            <Text style={styles.detailValue}>ROBLOX</Text>
          </View>
          <View style={styles.detailCell}>
            <Text style={styles.detailLabel}>CHAVES</Text>
            <Text style={styles.detailValue}>FREE/VIP</Text>
          </View>
        </View>

        <View style={styles.credentialBox}>
          <Text style={styles.credentialText}>{LOGIN_IMAGE_ASSET}</Text>
        </View>

        <Text style={styles.section}>GERAR LOADSTRING</Text>
        <Text style={styles.muted}>
          Cole o ID público do menu criado em “Menus e chaves”. O aplicativo monta o loader final usando automaticamente o login-base oficial.
        </Text>

        <TextInput
          value={menuId}
          onChangeText={setMenuId}
          style={styles.input}
          placeholder="menu_xxxxxxxxx"
          placeholderTextColor="#666"
          autoCapitalize="none"
          autoCorrect={false}
        />

        <View style={styles.credentialBox}>
          <Text style={styles.credentialText}>
            {loader || "O loadstring aparecerá aqui quando o menuId estiver válido."}
          </Text>
        </View>

        <Pressable
          style={[styles.featureCard, !isValid && { opacity: 0.45 }]}
          disabled={!isValid}
          onPress={copyLoader}
        >
          <View style={styles.featureIcon}><Text style={styles.featureIconText}>⌘</Text></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.cardTitle}>Copiar loadstring</Text>
            <Text style={styles.muted}>Pronto para colar no executor.</Text>
          </View>
          <Text style={styles.cardArrow}>›</Text>
        </Pressable>

        <Pressable style={styles.featureCard} onPress={onMenus}>
          <View style={styles.featureIcon}><Text style={styles.featureIconText}>＋</Text></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.cardTitle}>Abrir Menus e chaves</Text>
            <Text style={styles.muted}>Cadastrar menu, gerar FREE/VIP e copiar o menuId.</Text>
          </View>
          <Text style={styles.cardArrow}>›</Text>
        </Pressable>

        <Pressable style={styles.featureCard} onPress={copyBaseUrl}>
          <View style={styles.featureIcon}><Text style={styles.featureIconText}>↗</Text></View>
          <View style={{ flex: 1 }}>
            <Text style={styles.cardTitle}>Copiar URL do login-base</Text>
            <Text style={styles.muted}>Referência técnica do GrupoLuaLogin.lua.</Text>
          </View>
          <Text style={styles.cardArrow}>›</Text>
        </Pressable>

        <Text style={styles.small}>
          O loader contém apenas o menuId público e a URL do login-base. As chaves de acesso não são gravadas nele.
        </Text>
      </ScrollView>
    </SafeAreaView>
  );
}
