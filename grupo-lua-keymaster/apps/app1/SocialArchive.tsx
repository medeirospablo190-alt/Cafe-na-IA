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
          <Text style={s.title}>Mais publicações</Text>
          <Text style={s.subtitle}>Histórico paginado além das 40 publicações mais recentes.</Text>
        </View>
        <Pressable style={s.refresh} disabled={loadingMore || Boolean(busyId)} onPress={() => { loadPage({ reset: true }).catch(() => {}); }}>
          <Text style={s.refreshText}>↻</Text>
        </Pressable>
      </View>

      {posts.map((post) => (
        <View key={post.id} style={[s.card, post.pinned && s.pinned]}>
          <View style={s.row}>
            <View style={{ flex: 1 }}>
              <Text style={s.author}>{post.author.publicName}{post.author.role === "DEV" ? " • DEV" : ""}</Text>
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
            <Pressable disabled={Boolean(busyId)} style={[s.action, post.reactions.liked && s.active]} onPress={() => { toggleLike(post).catch(() => {}); }}>
              <Text style={s.actionText}>{post.reactions.liked ? "♥" : "♡"} {post.reactions.likeCount}</Text>
            </Pressable>
            <Pressable disabled={Boolean(busyId)} style={[s.action, post.reactions.favorited && s.active]} onPress={() => { toggleFavorite(post).catch(() => {}); }}>
              <Text style={s.actionText}>{post.reactions.favorited ? "★" : "☆"} {post.reactions.favoriteCount}</Text>
            </Pressable>
            <Pressable disabled={Boolean(busyId)} style={s.action} onPress={() => { copyPost(post).catch(() => {}); }}>
              <Text style={s.actionText}>COPIAR</Text>
            </Pressable>
          </View>
          <Text style={s.counts}>{post.reactions.commentCount} comentário(s)</Text>
        </View>
      ))}

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
    marginTop: 18,
    paddingTop: 15,
    borderTopWidth: 1,
    borderTopColor: "rgba(255,255,255,0.12)"
  },
  header: { flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 2 },
  title: { color: "#FFFFFF", fontSize: 17, fontWeight: "900" },
  subtitle: { color: "rgba(235,235,240,0.58)", fontSize: 9, lineHeight: 14, marginTop: 3 },
  refresh: {
    width: 38,
    height: 38,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(5,5,7,0.22)",
    alignItems: "center",
    justifyContent: "center"
  },
  refreshText: { color: "#D4B8E6", fontSize: 17 },
  card: {
    marginTop: 10,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.30)",
    padding: 13
  },
  pinned: { borderColor: "rgba(222,66,74,0.50)" },
  row: { flexDirection: "row", alignItems: "center", gap: 8 },
  author: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  meta: { color: "rgba(225,225,232,0.56)", fontSize: 8, marginTop: 3 },
  pin: { color: "#FF858B", fontSize: 7, fontWeight: "900" },
  comment: {
    color: "#ECE8EF",
    fontSize: 10,
    lineHeight: 15,
    marginTop: 10,
    borderLeftWidth: 2,
    borderLeftColor: "rgba(192,137,225,0.62)",
    paddingLeft: 8
  },
  postTitle: { color: "#FFFFFF", fontSize: 13, fontWeight: "900", marginTop: 10 },
  codeBox: {
    marginTop: 7,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.13)",
    backgroundColor: "rgba(0,0,0,0.30)",
    padding: 10
  },
  code: { color: "#DFDFE4", fontFamily: "monospace", fontSize: 8, lineHeight: 13 },
  preview: { color: "rgba(225,225,232,0.55)", fontSize: 8, marginTop: 5 },
  actions: { flexDirection: "row", gap: 6, marginTop: 9 },
  action: {
    flex: 1,
    minHeight: 34,
    borderRadius: 9,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.16)",
    alignItems: "center",
    justifyContent: "center"
  },
  active: {
    borderColor: "rgba(189,133,224,0.48)",
    backgroundColor: "rgba(59,29,76,0.30)"
  },
  actionText: { color: "rgba(245,245,248,0.80)", fontSize: 7, fontWeight: "900" },
  counts: { color: "rgba(225,225,232,0.50)", fontSize: 8, marginTop: 7 },
  more: {
    minHeight: 46,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(210,171,235,0.30)",
    backgroundColor: "rgba(30,16,37,0.30)",
    alignItems: "center",
    justifyContent: "center",
    marginTop: 12
  },
  moreText: { color: "#DCC8E9", fontSize: 8, fontWeight: "900" },
  end: { color: "rgba(225,225,232,0.45)", fontSize: 8, textAlign: "center", marginVertical: 14 },
  disabled: { opacity: 0.42 }
});