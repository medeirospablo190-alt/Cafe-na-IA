import { useEffect, useRef, useState } from "react";
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from "react-native";
import * as Clipboard from "expo-clipboard";
import {
  type SocialPost,
  getSocialPost,
  listSocialFeed,
  setSocialFavorite,
  setSocialLike
} from "./social-api";

const FIRST_PAGE_OFFSET = 40;
const PAGE_SIZE = 40;

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function SocialArchive({ sessionToken, deviceToken }: {
  sessionToken: string;
  deviceToken: string;
}) {
  const [posts, setPosts] = useState<SocialPost[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const mounted = useRef(true);
  const nextOffset = useRef(FIRST_PAGE_OFFSET);
  const requestVersion = useRef(0);

  async function loadPage({ reset = false }: { reset?: boolean } = {}) {
    const version = ++requestVersion.current;
    if (reset) {
      nextOffset.current = FIRST_PAGE_OFFSET;
      setLoading(true);
    } else {
      setLoadingMore(true);
    }

    try {
      const result = await listSocialFeed(
        sessionToken,
        deviceToken,
        PAGE_SIZE,
        reset ? FIRST_PAGE_OFFSET : nextOffset.current
      );
      if (!mounted.current || version !== requestVersion.current) return;

      setPosts((current) => {
        const base = reset ? [] : current;
        const known = new Set(base.map((post) => post.id));
        return [...base, ...result.posts.filter((post) => !known.has(post.id))];
      });
      nextOffset.current = (reset ? FIRST_PAGE_OFFSET : nextOffset.current) + result.posts.length;
      setHasMore(result.hasMore);
    } catch (error) {
      if (mounted.current && version === requestVersion.current) {
        Alert.alert("Mais publicações indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar o restante do feed.");
      }
    } finally {
      if (mounted.current && version === requestVersion.current) {
        setLoading(false);
        setLoadingMore(false);
      }
    }
  }

  function patchPost(postId: string, updater: (post: SocialPost) => SocialPost) {
    setPosts((current) => current.map((post) => post.id === postId ? updater(post) : post));
  }

  async function toggleLike(post: SocialPost) {
    if (busyId) return;
    setBusyId(`like:${post.id}`);
    try {
      const result = await setSocialLike(sessionToken, deviceToken, post.id, !post.reactions.liked);
      if (!mounted.current) return;
      patchPost(post.id, (current) => ({
        ...current,
        reactions: { ...current.reactions, liked: result.liked, likeCount: result.likeCount }
      }));
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao curtir", error instanceof Error ? error.message : "Não foi possível atualizar a curtida.");
    } finally {
      if (mounted.current) setBusyId(null);
    }
  }

  async function toggleFavorite(post: SocialPost) {
    if (busyId) return;
    setBusyId(`favorite:${post.id}`);
    try {
      const result = await setSocialFavorite(sessionToken, deviceToken, post.id, !post.reactions.favorited);
      if (!mounted.current) return;
      patchPost(post.id, (current) => ({
        ...current,
        reactions: { ...current.reactions, favorited: result.favorite, favoriteCount: result.favoriteCount }
      }));
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao favoritar", error instanceof Error ? error.message : "Não foi possível atualizar o favorito.");
    } finally {
      if (mounted.current) setBusyId(null);
    }
  }

  async function copyPost(post: SocialPost) {
    if (busyId) return;
    setBusyId(`copy:${post.id}`);
    try {
      let content = post.item.content;
      if (post.item.truncated) {
        content = (await getSocialPost(sessionToken, deviceToken, post.id)).post.item.content;
      }
      await Clipboard.setStringAsync(content);
      if (mounted.current) Alert.alert("Copiado", `${post.item.title} foi copiado por completo.`);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar a publicação.");
    } finally {
      if (mounted.current) setBusyId(null);
    }
  }

  useEffect(() => {
    mounted.current = true;
    loadPage({ reset: true }).catch(() => {});
    return () => {
      mounted.current = false;
      requestVersion.current += 1;
    };
  }, [sessionToken, deviceToken]);

  if (loading) {
    return <ActivityIndicator style={{ marginVertical: 18 }} />;
  }

  if (posts.length === 0 && !hasMore) return null;

  return (
    <View style={s.root}>
      <View style={s.header}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>Histórico Social</Text>
          <Text style={s.subtitle}>Publicações anteriores às 40 mais recentes.</Text>
        </View>
        <Pressable
          style={s.refresh}
          disabled={loadingMore || Boolean(busyId)}
          onPress={() => { loadPage({ reset: true }).catch(() => {}); }}
          accessibilityRole="button"
          accessibilityLabel="Atualizar histórico social"
        >
          <Text style={s.refreshText}>ATUALIZAR</Text>
        </Pressable>
      </View>

      <View style={s.list}>
        {posts.map((post) => (
          <View key={post.id} style={[s.post, post.pinned && s.pinned]}>
            <View style={s.row}>
              <View style={{ flex: 1 }}>
                <View style={s.authorRow}>
                  <Text style={s.author}>{post.author.publicName}</Text>
                  <Text style={[s.role, post.author.role === "DEV" && s.roleDev]}>{post.author.role}</Text>
                </View>
                <Text style={s.meta}>{dateText(post.createdAt)} • {post.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
              </View>
              {post.pinned ? <Text style={s.pin}>FIXADO</Text> : null}
            </View>

            {post.comment ? <Text style={s.comment}>{post.comment}</Text> : null}
            <Text style={s.postTitle}>{post.item.title}</Text>
            <View style={s.codeBox}>
              <Text numberOfLines={6} style={s.code}>{post.item.content}</Text>
            </View>
            {post.item.truncated ? <Text style={s.preview}>Prévia reduzida. Copiar busca o conteúdo completo.</Text> : null}

            <View style={s.actions}>
              <Pressable
                disabled={Boolean(busyId)}
                style={[s.action, post.reactions.liked && s.active]}
                onPress={() => { toggleLike(post).catch(() => {}); }}
              >
                <Text style={[s.actionText, post.reactions.liked && s.actionTextActive]}>
                  {post.reactions.liked ? "CURTIDO" : "CURTIR"}  {post.reactions.likeCount}
                </Text>
              </Pressable>
              <Pressable
                disabled={Boolean(busyId)}
                style={[s.action, post.reactions.favorited && s.active]}
                onPress={() => { toggleFavorite(post).catch(() => {}); }}
              >
                <Text style={[s.actionText, post.reactions.favorited && s.actionTextActive]}>
                  {post.reactions.favorited ? "FAVORITADO" : "FAVORITAR"}  {post.reactions.favoriteCount}
                </Text>
              </Pressable>
              <Pressable disabled={Boolean(busyId)} style={s.actionCompact} onPress={() => { copyPost(post).catch(() => {}); }}>
                <Text style={s.actionText}>COPIAR</Text>
              </Pressable>
            </View>
            <Text style={s.counts}>{post.reactions.commentCount} comentário{post.reactions.commentCount === 1 ? "" : "s"}</Text>
          </View>
        ))}
      </View>

      {hasMore ? (
        <Pressable
          style={[s.more, (loadingMore || Boolean(busyId)) && s.disabled]}
          disabled={loadingMore || Boolean(busyId)}
          onPress={() => { loadPage().catch(() => {}); }}
        >
          <Text style={s.moreText}>{loadingMore ? "CARREGANDO..." : "CARREGAR MAIS PUBLICAÇÕES"}</Text>
        </Pressable>
      ) : posts.length > 0 ? <Text style={s.end}>Fim do histórico disponível.</Text> : null}
    </View>
  );
}

const s = StyleSheet.create({
  root: {
    marginTop: 2,
    paddingTop: 4
  },
  header: { flexDirection: "row", alignItems: "center", gap: 8, paddingHorizontal: 3, paddingBottom: 8 },
  title: { color: "#FFFFFF", fontSize: 13, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.54)", fontSize: 8, lineHeight: 13, marginTop: 2 },
  refresh: {
    minHeight: 34,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(0,0,0,0.12)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 10
  },
  refreshText: { color: "rgba(245,245,248,0.72)", fontSize: 7, fontWeight: "900", letterSpacing: 0.4 },
  list: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: "rgba(255,255,255,0.12)"
  },
  post: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "rgba(255,255,255,0.13)",
    backgroundColor: "rgba(3,3,5,0.07)",
    paddingHorizontal: 4,
    paddingVertical: 12
  },
  pinned: { borderTopWidth: 1, borderTopColor: "rgba(255,38,56,0.55)" },
  row: { flexDirection: "row", alignItems: "center", gap: 8 },
  authorRow: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  author: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  role: {
    color: "#FFFFFF",
    fontSize: 6,
    fontWeight: "900",
    backgroundColor: "rgba(91,32,38,0.68)",
    borderRadius: 4,
    paddingHorizontal: 5,
    paddingVertical: 2
  },
  roleDev: { backgroundColor: "rgba(121,17,24,0.84)" },
  meta: { color: "rgba(225,225,232,0.52)", fontSize: 7, marginTop: 3 },
  pin: { color: "#FF6873", fontSize: 7, fontWeight: "900", letterSpacing: 0.4 },
  comment: {
    color: "#ECECF0",
    fontSize: 10,
    lineHeight: 15,
    marginTop: 9,
    borderLeftWidth: 2,
    borderLeftColor: "rgba(255,38,56,0.55)",
    paddingLeft: 8
  },
  postTitle: { color: "#FFFFFF", fontSize: 13, fontWeight: "900", marginTop: 9 },
  codeBox: {
    marginTop: 7,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: "rgba(255,255,255,0.10)",
    backgroundColor: "rgba(0,0,0,0.18)",
    paddingHorizontal: 9,
    paddingVertical: 9
  },
  code: { color: "#DFDFE4", fontFamily: "monospace", fontSize: 8, lineHeight: 13 },
  preview: { color: "rgba(225,225,232,0.52)", fontSize: 8, marginTop: 5 },
  actions: { flexDirection: "row", alignItems: "center", gap: 6, marginTop: 9 },
  action: {
    flex: 1,
    minHeight: 32,
    borderRadius: 7,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(0,0,0,0.12)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 6
  },
  actionCompact: {
    minWidth: 66,
    minHeight: 32,
    borderRadius: 7,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(0,0,0,0.12)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 8
  },
  active: {
    borderColor: "rgba(255,38,56,0.48)",
    backgroundColor: "rgba(83,7,14,0.26)"
  },
  actionText: { color: "rgba(245,245,248,0.76)", fontSize: 7, fontWeight: "900" },
  actionTextActive: { color: "#FF8A92" },
  counts: { color: "rgba(225,225,232,0.46)", fontSize: 8, marginTop: 7 },
  more: {
    minHeight: 42,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "rgba(255,38,56,0.30)",
    backgroundColor: "rgba(70,5,11,0.18)",
    alignItems: "center",
    justifyContent: "center",
    marginTop: 10
  },
  moreText: { color: "#FF8A92", fontSize: 8, fontWeight: "900" },
  end: { color: "rgba(225,225,232,0.42)", fontSize: 8, textAlign: "center", marginVertical: 12 },
  disabled: { opacity: 0.42 }
});