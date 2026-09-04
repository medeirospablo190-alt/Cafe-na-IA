import { useEffect, useState } from "react";
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from "react-native";
import * as Clipboard from "expo-clipboard";
import { getFeedPost, listFeedPosts, type FeedPost } from "./api";

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function SocialFeedScreen({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [posts, setPosts] = useState<FeedPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [copyingId, setCopyingId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function reload() {
    if (loading && posts.length > 0) return;
    setLoading(true);
    setMessage(null);
    try {
      const result = await listFeedPosts(sessionToken, deviceToken);
      setPosts(result.posts);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Não foi possível carregar o feed.");
    } finally {
      setLoading(false);
    }
  }

  async function copyPost(post: FeedPost) {
    if (copyingId) return;
    setCopyingId(post.id);
    try {
      let content = post.item.content;
      if (post.item.truncated) {
        const result = await getFeedPost(sessionToken, deviceToken, post.id);
        content = result.post.item.content;
      }
      await Clipboard.setStringAsync(content);
      setMessage(`${post.item.title} copiado por completo.`);
    } catch (error) {
      Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar a publicação.");
    } finally {
      setCopyingId(null);
    }
  }

  useEffect(() => {
    reload().catch(() => {});
  }, [sessionToken, deviceToken]);

  return (
    <View style={local.root}>
      <View style={local.header}>
        <View style={{ flex: 1 }}>
          <Text style={local.title}>Feed de notícias</Text>
          <Text style={local.subtitle}>Publicações compartilhadas pelo App 1.</Text>
        </View>
        <Pressable style={[local.refresh, loading && local.disabled]} disabled={loading} onPress={() => reload()}>
          <Text style={local.refreshText}>↻</Text>
        </Pressable>
      </View>

      {loading ? <ActivityIndicator style={{ marginVertical: 28 }} /> : null}
      {message ? <Text style={local.message}>{message}</Text> : null}

      {!loading && posts.length === 0 ? (
        <View style={local.empty}>
          <Text style={local.emptyTitle}>Feed vazio</Text>
          <Text style={local.emptyText}>Compartilhe um código ou loadstring pela aba Arquivos para criar a primeira publicação.</Text>
        </View>
      ) : null}

      {!loading ? posts.map((post) => (
        <View key={post.id} style={local.post}>
          <View style={local.postHeader}>
            <View style={local.avatar}>
              <Text style={local.avatarText}>{post.author.publicName.slice(0, 1).toUpperCase()}</Text>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={local.author}>{post.author.publicName}</Text>
              <Text style={local.meta}>{formatDate(post.createdAt)} • expira {formatDate(post.expiresAt)}</Text>
            </View>
            <Text style={local.kind}>{post.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
          </View>

          <Text style={local.postTitle}>{post.item.title}</Text>
          <View style={local.codeBox}>
            <Text numberOfLines={8} style={local.code}>{post.item.content}</Text>
          </View>
          {post.item.truncated ? <Text style={local.previewNote}>Prévia reduzida para manter o feed leve. Copiar baixa o conteúdo completo.</Text> : null}
          <Pressable
            style={[local.copyButton, copyingId === post.id && local.disabled]}
            disabled={Boolean(copyingId)}
            onPress={() => copyPost(post)}
          >
            <Text style={local.copyText}>
              {copyingId === post.id ? "COPIANDO..." : `COPIAR ${post.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}`}
            </Text>
          </Pressable>
        </View>
      )) : null}
    </View>
  );
}

const local = StyleSheet.create({
  root: { flex: 1 },
  header: { flexDirection: "row", alignItems: "center", marginBottom: 6 },
  title: { color: "#FFFFFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "#74747C", fontSize: 11, marginTop: 3 },
  refresh: { width: 44, height: 44, borderRadius: 14, borderWidth: 1, borderColor: "#2A2A30", alignItems: "center", justifyContent: "center" },
  refreshText: { color: "#C0A6D8", fontSize: 20 },
  disabled: { opacity: 0.45 },
  message: { color: "#B9A1CC", fontSize: 11, marginTop: 10 },
  empty: { marginTop: 18, borderRadius: 18, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#09090C", padding: 26, alignItems: "center" },
  emptyTitle: { color: "#FFFFFF", fontSize: 16, fontWeight: "900" },
  emptyText: { color: "#777780", fontSize: 12, lineHeight: 18, textAlign: "center", marginTop: 6 },
  post: { marginTop: 12, borderRadius: 18, borderWidth: 1, borderColor: "#25252B", backgroundColor: "#09090C", padding: 14 },
  postHeader: { flexDirection: "row", alignItems: "center", gap: 10 },
  avatar: { width: 38, height: 38, borderRadius: 99, backgroundColor: "#1B1027", borderWidth: 1, borderColor: "#5E397D", alignItems: "center", justifyContent: "center" },
  avatarText: { color: "#D1A0FF", fontWeight: "900" },
  author: { color: "#FFFFFF", fontWeight: "900", fontSize: 13 },
  meta: { color: "#67676F", fontSize: 9, marginTop: 2 },
  kind: { color: "#B77BEE", fontWeight: "900", fontSize: 8, borderWidth: 1, borderColor: "#4C3165", borderRadius: 8, paddingHorizontal: 8, paddingVertical: 5 },
  postTitle: { color: "#F2F2F4", fontSize: 16, fontWeight: "900", marginTop: 14 },
  codeBox: { marginTop: 10, borderRadius: 12, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#050507", padding: 12 },
  code: { color: "#CACAD0", fontFamily: "monospace", fontSize: 10, lineHeight: 15 },
  previewNote: { color: "#777780", fontSize: 9, lineHeight: 14, marginTop: 7 },
  copyButton: { marginTop: 10, minHeight: 40, borderRadius: 10, borderWidth: 1, borderColor: "#303036", alignItems: "center", justifyContent: "center" },
  copyText: { color: "#D8D8DD", fontSize: 9, fontWeight: "900" }
});
