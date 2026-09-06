import { useEffect, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Clipboard from "expo-clipboard";
import type { App1Role } from "./api";
import {
  type PublicProfileView,
  type SocialComment,
  type SocialNotification,
  type SocialNotificationKind,
  type SocialPost,
  createSocialComment,
  deleteSocialComment,
  getProfileFavorites,
  getProfilePosts,
  getPublicProfile,
  getSocialPost,
  listPostFavorites,
  listSocialComments,
  listSocialFeed,
  listSocialNotifications,
  markSocialNotificationsRead,
  searchPublicProfiles,
  setSocialFavorite,
  setSocialLike,
  setSocialPostPinned
} from "./social-api";

const NOTIFICATION_TABS: Array<{ key: "ALL" | SocialNotificationKind; label: string }> = [
  { key: "ALL", label: "TODAS" },
  { key: "LIKE", label: "CURTIDAS" },
  { key: "COMMENT", label: "COMENTÁRIOS" },
  { key: "FAVORITE", label: "FAVORITOS" }
];

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function profileInitial(profile?: { publicName?: string | null }) {
  return String(profile?.publicName || "L").slice(0, 1).toUpperCase();
}

function notificationText(item: SocialNotification) {
  const who = item.actor?.publicName || "GRUPO LUA";
  if (item.kind === "LIKE") return `${who} curtiu sua publicação.`;
  if (item.kind === "COMMENT") return `${who} comentou ou respondeu sua publicação.`;
  if (item.kind === "FAVORITE") return `${who} favoritou sua publicação.`;
  return "Novo aviso dos desenvolvedores.";
}

function ProfileGlyph() {
  return (
    <View style={s.profileGlyph}>
      <View style={s.profileHead} />
      <View style={s.profileShoulders} />
    </View>
  );
}

export function SocialFeedScreenV4({
  sessionToken,
  deviceToken,
  viewerRole = "ADM",
  onOpenChat,
  onOpenProfile
}: {
  sessionToken: string;
  deviceToken: string;
  viewerRole?: App1Role;
  onOpenChat: () => void;
  onOpenProfile: () => void;
}) {
  const [posts, setPosts] = useState<SocialPost[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [expandedPostId, setExpandedPostId] = useState<string | null>(null);
  const [comments, setComments] = useState<Record<string, SocialComment[]>>({});
  const [commentsLoading, setCommentsLoading] = useState<string | null>(null);
  const [commentDraft, setCommentDraft] = useState("");
  const [replyTo, setReplyTo] = useState<SocialComment | null>(null);
  const [search, setSearch] = useState("");
  const [searching, setSearching] = useState(false);
  const [profiles, setProfiles] = useState<PublicProfileView[]>([]);
  const [profileOpen, setProfileOpen] = useState<PublicProfileView | null>(null);
  const [profilePosts, setProfilePosts] = useState<SocialPost[]>([]);
  const [profileFavorites, setProfileFavorites] = useState<SocialPost[]>([]);
  const [profileCounts, setProfileCounts] = useState({ posts: 0, favorites: 0 });
  const [profileTab, setProfileTab] = useState<"POSTS" | "FAVORITES">("POSTS");
  const [profileLoading, setProfileLoading] = useState(false);
  const [favoritesOpen, setFavoritesOpen] = useState<PublicProfileView[] | null>(null);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [notificationKind, setNotificationKind] = useState<"ALL" | SocialNotificationKind>("ALL");
  const [notifications, setNotifications] = useState<SocialNotification[]>([]);
  const [unread, setUnread] = useState<Record<"ALL" | SocialNotificationKind, number>>({
    ALL: 0,
    LIKE: 0,
    COMMENT: 0,
    FAVORITE: 0,
    ANNOUNCEMENT: 0
  });
  const mounted = useRef(true);
  const requestVersion = useRef(0);

  async function reload(showSpinner = true) {
    const version = ++requestVersion.current;
    if (showSpinner) setLoading(true);
    setMessage(null);
    try {
      const [feed, notices] = await Promise.all([
        listSocialFeed(sessionToken, deviceToken, 40, 0),
        listSocialNotifications(sessionToken, deviceToken).catch(() => null)
      ]);
      if (!mounted.current || version !== requestVersion.current) return;
      setPosts(feed.posts);
      if (notices) {
        setUnread(notices.unread);
        if (!notificationsOpen) setNotifications(notices.notifications);
      }
    } catch (error) {
      if (mounted.current && version === requestVersion.current) {
        setMessage(error instanceof Error ? error.message : "Não foi possível carregar o Social.");
      }
    } finally {
      if (mounted.current && version === requestVersion.current && showSpinner) setLoading(false);
    }
  }

  function patchPost(postId: string, updater: (post: SocialPost) => SocialPost) {
    setPosts((current) => current.map((post) => post.id === postId ? updater(post) : post));
    setProfilePosts((current) => current.map((post) => post.id === postId ? updater(post) : post));
    setProfileFavorites((current) => current.map((post) => post.id === postId ? updater(post) : post));
  }

  async function toggleLike(post: SocialPost) {
    if (busyAction) return;
    setBusyAction(`like:${post.id}`);
    try {
      const result = await setSocialLike(sessionToken, deviceToken, post.id, !post.reactions.liked);
      if (!mounted.current) return;
      patchPost(post.id, (current) => ({
        ...current,
        reactions: { ...current.reactions, liked: result.liked, likeCount: result.likeCount }
      }));
    } catch (error) {
      if (mounted.current) Alert.alert("Não foi possível curtir", error instanceof Error ? error.message : "Falha no Social.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  async function toggleFavorite(post: SocialPost) {
    if (busyAction) return;
    setBusyAction(`favorite:${post.id}`);
    try {
      const result = await setSocialFavorite(sessionToken, deviceToken, post.id, !post.reactions.favorited);
      if (!mounted.current) return;
      patchPost(post.id, (current) => ({
        ...current,
        reactions: { ...current.reactions, favorited: result.favorite, favoriteCount: result.favoriteCount }
      }));
    } catch (error) {
      if (mounted.current) Alert.alert("Não foi possível favoritar", error instanceof Error ? error.message : "Falha no Social.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  async function copyPost(post: SocialPost) {
    if (busyAction) return;
    setBusyAction(`copy:${post.id}`);
    try {
      let content = post.item.content;
      if (post.item.truncated) content = (await getSocialPost(sessionToken, deviceToken, post.id)).post.item.content;
      await Clipboard.setStringAsync(content);
      if (mounted.current) setMessage(`${post.item.title} copiado.`);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  async function openComments(post: SocialPost) {
    if (expandedPostId === post.id) {
      setExpandedPostId(null);
      setReplyTo(null);
      setCommentDraft("");
      return;
    }
    setExpandedPostId(post.id);
    setReplyTo(null);
    setCommentDraft("");
    if (comments[post.id]) return;
    setCommentsLoading(post.id);
    try {
      const result = await listSocialComments(sessionToken, deviceToken, post.id, 60, 0);
      if (mounted.current) setComments((current) => ({ ...current, [post.id]: result.comments }));
    } catch (error) {
      if (mounted.current) Alert.alert("Comentários indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar comentários.");
    } finally {
      if (mounted.current) setCommentsLoading(null);
    }
  }

  async function submitComment(post: SocialPost) {
    const text = commentDraft.trim();
    if (!text || busyAction) return;
    setBusyAction(`comment:${post.id}`);
    setCommentDraft("");
    try {
      const result = await createSocialComment(sessionToken, deviceToken, post.id, text, replyTo?.id || null);
      if (!mounted.current) return;
      setComments((current) => ({ ...current, [post.id]: [...(current[post.id] || []), result.comment] }));
      patchPost(post.id, (current) => ({
        ...current,
        reactions: { ...current.reactions, commentCount: current.reactions.commentCount + 1 }
      }));
      setReplyTo(null);
    } catch (error) {
      if (mounted.current) {
        setCommentDraft(text);
        Alert.alert("Comentário não enviado", error instanceof Error ? error.message : "Falha ao comentar.");
      }
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  function confirmDeleteComment(post: SocialPost, comment: SocialComment) {
    Alert.alert("Apagar comentário?", "O comentário e respostas ligadas a ele serão removidos.", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Apagar",
        style: "destructive",
        onPress: async () => {
          if (busyAction) return;
          setBusyAction(`delete-comment:${comment.id}`);
          try {
            await deleteSocialComment(sessionToken, deviceToken, comment.id);
            if (!mounted.current) return;
            const before = comments[post.id] || [];
            const ids = new Set<string>([comment.id]);
            let changed = true;
            while (changed) {
              changed = false;
              for (const item of before) {
                if (item.parentCommentId && ids.has(item.parentCommentId) && !ids.has(item.id)) {
                  ids.add(item.id);
                  changed = true;
                }
              }
            }
            setComments((current) => ({
              ...current,
              [post.id]: (current[post.id] || []).filter((item) => !ids.has(item.id))
            }));
            patchPost(post.id, (current) => ({
              ...current,
              reactions: { ...current.reactions, commentCount: Math.max(0, current.reactions.commentCount - ids.size) }
            }));
          } catch (error) {
            if (mounted.current) Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível apagar.");
          } finally {
            if (mounted.current) setBusyAction(null);
          }
        }
      }
    ]);
  }

  async function showFavorites(post: SocialPost) {
    if (post.reactions.favoriteCount <= 0) return;
    try {
      const result = await listPostFavorites(sessionToken, deviceToken, post.id);
      if (mounted.current) setFavoritesOpen(result.profiles);
    } catch (error) {
      if (mounted.current) Alert.alert("Favoritos indisponíveis", error instanceof Error ? error.message : "Não foi possível abrir a lista.");
    }
  }

  async function togglePin(post: SocialPost) {
    if (viewerRole !== "DEV" || busyAction) return;
    setBusyAction(`pin:${post.id}`);
    try {
      await setSocialPostPinned(sessionToken, deviceToken, post.id, !post.pinned);
      if (mounted.current) await reload(false);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao fixar", error instanceof Error ? error.message : "A publicação não pôde ser fixada.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  async function openProfile(profile: PublicProfileView | SocialPost["author"] | SocialComment["author"]) {
    if (!profile.profileId) return;
    setProfileLoading(true);
    setProfileTab("POSTS");
    try {
      const [detail, postsResult, favoritesResult] = await Promise.all([
        getPublicProfile(sessionToken, deviceToken, profile.profileId),
        getProfilePosts(sessionToken, deviceToken, profile.profileId),
        getProfileFavorites(sessionToken, deviceToken, profile.profileId)
      ]);
      if (!mounted.current) return;
      setProfileOpen(detail.profile);
      setProfileCounts(detail.counts);
      setProfilePosts(postsResult.posts);
      setProfileFavorites(favoritesResult.posts);
      setProfiles([]);
      setSearch("");
    } catch (error) {
      if (mounted.current) Alert.alert("Perfil indisponível", error instanceof Error ? error.message : "Não foi possível abrir o perfil.");
    } finally {
      if (mounted.current) setProfileLoading(false);
    }
  }

  async function openNotifications() {
    setNotificationsOpen(true);
    try {
      const result = await listSocialNotifications(
        sessionToken,
        deviceToken,
        notificationKind === "ALL" ? undefined : notificationKind
      );
      if (!mounted.current) return;
      setNotifications(result.notifications);
      setUnread(result.unread);
    } catch (error) {
      if (mounted.current) Alert.alert("Notificações indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar as notificações.");
    }
  }

  async function changeNotificationKind(kind: "ALL" | SocialNotificationKind) {
    setNotificationKind(kind);
    try {
      const result = await listSocialNotifications(sessionToken, deviceToken, kind === "ALL" ? undefined : kind);
      if (mounted.current) {
        setNotifications(result.notifications);
        setUnread(result.unread);
      }
    } catch {
      if (mounted.current) setNotifications([]);
    }
  }

  async function readNotifications() {
    try {
      await markSocialNotificationsRead(
        sessionToken,
        deviceToken,
        notificationKind === "ALL" ? {} : { kind: notificationKind }
      );
      if (mounted.current) await changeNotificationKind(notificationKind);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível marcar como lidas.");
    }
  }

  useEffect(() => {
    mounted.current = true;
    reload(true).catch(() => {});
    return () => {
      mounted.current = false;
      requestVersion.current += 1;
    };
  }, [sessionToken, deviceToken]);

  useEffect(() => {
    const q = search.trim();
    if (q.length < 2) {
      setProfiles([]);
      setSearching(false);
      return;
    }
    let cancelled = false;
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const result = await searchPublicProfiles(sessionToken, deviceToken, q, 15, 0);
        if (!cancelled && mounted.current) setProfiles(result.profiles);
      } catch {
        if (!cancelled && mounted.current) setProfiles([]);
      } finally {
        if (!cancelled && mounted.current) setSearching(false);
      }
    }, 450);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [search, sessionToken, deviceToken]);

  const currentProfilePosts = profileTab === "POSTS" ? profilePosts : profileFavorites;

  return (
    <View style={s.root}>
      <View style={s.topBar}>
        <Pressable
          style={s.topIcon}
          onPress={onOpenProfile}
          accessibilityRole="button"
          accessibilityLabel="Abrir perfil"
        >
          <ProfileGlyph />
        </Pressable>
        <View style={s.topSpacer} />
        <Pressable
          style={s.topIcon}
          onPress={onOpenChat}
          accessibilityRole="button"
          accessibilityLabel="Abrir chat"
        >
          <Text style={s.chatIcon}>✉</Text>
        </Pressable>
        <Pressable
          style={s.topIcon}
          onPress={() => openNotifications().catch(() => {})}
          accessibilityRole="button"
          accessibilityLabel="Abrir notificações"
        >
          <Text style={s.notificationIcon}>♢</Text>
          {unread.ALL > 0 ? (
            <View style={s.counterBadge}>
              <Text style={s.counterBadgeText}>{unread.ALL > 99 ? "99+" : unread.ALL}</Text>
            </View>
          ) : null}
        </Pressable>
      </View>

      <TextInput
        value={search}
        onChangeText={setSearch}
        style={s.search}
        placeholder="Buscar perfil..."
        placeholderTextColor="rgba(235,235,240,0.55)"
        autoCapitalize="none"
        autoCorrect={false}
      />

      {searching ? <ActivityIndicator style={s.searchLoader} /> : null}
      {profiles.length > 0 ? (
        <View style={s.searchResults}>
          {profiles.map((profile) => (
            <Pressable
              key={profile.profileId || profile.publicName}
              style={s.profileResult}
              onPress={() => openProfile(profile).catch(() => {})}
            >
              <View style={[s.avatarSmall, profile.role === "DEV" && s.avatarDev]}>
                <Text style={s.avatarText}>{profileInitial(profile)}</Text>
              </View>
              <View style={s.profileResultText}>
                <View style={s.nameRow}>
                  <Text style={s.author}>{profile.publicName}</Text>
                  {profile.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                </View>
                <Text style={s.mini}>{profile.statusText || profile.bio || "Abrir perfil"}</Text>
              </View>
              <Text style={s.chevron}>›</Text>
            </Pressable>
          ))}
        </View>
      ) : null}

      {message ? (
        <Pressable style={s.messageBox} onPress={() => reload(true).catch(() => {})}>
          <Text style={s.message}>{message}</Text>
        </Pressable>
      ) : null}
      {loading ? <ActivityIndicator style={s.loader} /> : null}

      {!loading && posts.length === 0 ? (
        <View style={s.empty}>
          <Text style={s.emptyTitle}>Feed vazio</Text>
          <Text style={s.emptyText}>Publicações compartilhadas pela área Arquivos aparecerão aqui.</Text>
        </View>
      ) : null}

      {!loading ? posts.map((post) => {
        const postComments = comments[post.id] || [];
        const isExpanded = expandedPostId === post.id;
        return (
          <View key={post.id} style={[s.post, post.pinned && s.pinnedPost]}>
            {post.pinned ? <Text style={s.pinnedTag}>FIXADO PELO GRUPO LUA</Text> : null}
            <View style={s.postHeader}>
              <Pressable
                style={[s.avatar, post.author.role === "DEV" && s.avatarDev]}
                onPress={() => openProfile(post.author).catch(() => {})}
              >
                <Text style={s.avatarText}>{profileInitial(post.author)}</Text>
              </Pressable>
              <Pressable style={s.postIdentity} onPress={() => openProfile(post.author).catch(() => {})}>
                <View style={s.nameRow}>
                  <Text style={s.author}>{post.author.publicName}</Text>
                  {post.author.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                </View>
                <Text style={s.meta}>{dateText(post.createdAt)}</Text>
              </Pressable>
              <Text style={s.kind}>{post.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
            </View>

            {post.comment ? <Text style={s.postComment}>{post.comment}</Text> : null}
            <Text style={s.postTitle}>{post.item.title}</Text>
            <View style={s.codeBox}>
              <Text numberOfLines={8} style={s.code}>{post.item.content}</Text>
            </View>
            {post.item.truncated ? <Text style={s.previewNote}>Prévia reduzida. Copiar busca o conteúdo completo.</Text> : null}

            <View style={s.reactionRow}>
              <Pressable
                disabled={Boolean(busyAction)}
                style={s.reaction}
                onPress={() => toggleLike(post).catch(() => {})}
              >
                <Text style={[s.reactionIcon, post.reactions.liked && s.reactionIconActive]}>{post.reactions.liked ? "♥" : "♡"}</Text>
                <Text style={s.reactionCount}>{post.reactions.likeCount}</Text>
              </Pressable>
              <Pressable style={s.reaction} onPress={() => openComments(post).catch(() => {})}>
                <Text style={[s.commentGlyph, isExpanded && s.reactionIconActive]}>◌</Text>
                <Text style={s.reactionCount}>{post.reactions.commentCount}</Text>
              </Pressable>
              <Pressable
                disabled={Boolean(busyAction)}
                style={s.reaction}
                onPress={() => toggleFavorite(post).catch(() => {})}
              >
                <Text style={[s.reactionIcon, post.reactions.favorited && s.favoriteActive]}>{post.reactions.favorited ? "★" : "☆"}</Text>
                <Text style={s.reactionCount}>{post.reactions.favoriteCount}</Text>
              </Pressable>
              <View style={s.reactionSpacer} />
              <Pressable disabled={Boolean(busyAction)} style={s.copyButton} onPress={() => copyPost(post).catch(() => {})}>
                <Text style={s.copyText}>COPIAR</Text>
              </Pressable>
            </View>

            <View style={s.secondaryRow}>
              {post.reactions.favoriteCount > 0 ? (
                <Pressable onPress={() => showFavorites(post).catch(() => {})}>
                  <Text style={s.secondaryText}>Ver quem favoritou</Text>
                </Pressable>
              ) : null}
              {viewerRole === "DEV" ? (
                <Pressable disabled={Boolean(busyAction)} onPress={() => togglePin(post).catch(() => {})}>
                  <Text style={s.devAction}>{post.pinned ? "Desafixar" : "Fixar"}</Text>
                </Pressable>
              ) : null}
            </View>

            {isExpanded ? (
              <View style={s.commentsBox}>
                {commentsLoading === post.id ? (
                  <ActivityIndicator style={s.commentLoader} />
                ) : postComments.length === 0 ? (
                  <Text style={s.noComments}>Nenhum comentário ainda.</Text>
                ) : postComments.map((comment) => (
                  <View key={comment.id} style={[s.comment, comment.parentCommentId && s.reply]}>
                    <View style={s.commentHead}>
                      <Pressable onPress={() => openProfile(comment.author).catch(() => {})} style={s.nameRow}>
                        <Text style={s.commentAuthor}>{comment.author.publicName}</Text>
                        {comment.author.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                      </Pressable>
                      <Text style={s.mini}>{dateText(comment.createdAt)}</Text>
                    </View>
                    <Text style={s.commentText}>{comment.text}</Text>
                    <View style={s.commentActions}>
                      <Pressable onPress={() => { setReplyTo(comment); setCommentDraft(`@${comment.author.publicName} `); }}>
                        <Text style={s.commentActionText}>RESPONDER</Text>
                      </Pressable>
                      {comment.mine ? (
                        <Pressable onPress={() => confirmDeleteComment(post, comment)}>
                          <Text style={s.deleteText}>APAGAR</Text>
                        </Pressable>
                      ) : null}
                    </View>
                  </View>
                ))}

                {replyTo ? (
                  <View style={s.replying}>
                    <Text style={s.replyingText}>Respondendo a {replyTo.author.publicName}</Text>
                    <Pressable onPress={() => { setReplyTo(null); setCommentDraft(""); }}>
                      <Text style={s.cancelReply}>✕</Text>
                    </Pressable>
                  </View>
                ) : null}

                <View style={s.commentComposer}>
                  <TextInput
                    value={commentDraft}
                    onChangeText={setCommentDraft}
                    maxLength={1000}
                    multiline
                    editable={!busyAction}
                    style={s.commentInput}
                    placeholder="Escreva um comentário..."
                    placeholderTextColor="rgba(235,235,240,0.45)"
                  />
                  <Pressable
                    disabled={!commentDraft.trim() || Boolean(busyAction)}
                    style={[s.commentSend, (!commentDraft.trim() || busyAction) && s.disabled]}
                    onPress={() => submitComment(post).catch(() => {})}
                  >
                    <Text style={s.commentSendText}>ENVIAR</Text>
                  </Pressable>
                </View>
              </View>
            ) : null}
          </View>
        );
      }) : null}

      <Modal visible={notificationsOpen} transparent animationType="fade" onRequestClose={() => setNotificationsOpen(false)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <View style={s.modalHeader}>
              <Text style={s.modalTitle}>Notificações</Text>
              <Pressable onPress={() => setNotificationsOpen(false)}><Text style={s.modalClose}>✕</Text></Pressable>
            </View>
            <View style={s.tabRow}>
              {NOTIFICATION_TABS.map((tab) => (
                <Pressable
                  key={tab.key}
                  style={[s.tab, notificationKind === tab.key && s.tabActive]}
                  onPress={() => changeNotificationKind(tab.key).catch(() => {})}
                >
                  <Text style={[s.tabText, notificationKind === tab.key && s.tabTextActive]}>{tab.label}</Text>
                </Pressable>
              ))}
            </View>
            <Pressable style={s.readAll} onPress={() => readNotifications().catch(() => {})}>
              <Text style={s.readAllText}>MARCAR COMO LIDAS</Text>
            </Pressable>
            {notifications.length === 0 ? (
              <Text style={s.noComments}>Nenhuma notificação nesta categoria.</Text>
            ) : notifications.map((notice) => (
              <Pressable
                key={notice.id}
                style={[s.notice, !notice.read && s.noticeUnread]}
                onPress={() => {
                  if (notice.postId) {
                    setNotificationsOpen(false);
                    setExpandedPostId(notice.kind === "COMMENT" ? notice.postId : null);
                  }
                }}
              >
                <Text style={s.noticeText}>{notificationText(notice)}</Text>
                <Text style={s.mini}>{dateText(notice.createdAt)}{notice.postTitle ? ` • ${notice.postTitle}` : ""}</Text>
              </Pressable>
            ))}
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(favoritesOpen)} transparent animationType="fade" onRequestClose={() => setFavoritesOpen(null)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <View style={s.modalHeader}>
              <Text style={s.modalTitle}>Quem favoritou</Text>
              <Pressable onPress={() => setFavoritesOpen(null)}><Text style={s.modalClose}>✕</Text></Pressable>
            </View>
            {(favoritesOpen || []).map((profile) => (
              <Pressable
                key={profile.profileId || profile.publicName}
                style={s.profileResult}
                onPress={() => {
                  setFavoritesOpen(null);
                  openProfile(profile).catch(() => {});
                }}
              >
                <View style={[s.avatarSmall, profile.role === "DEV" && s.avatarDev]}>
                  <Text style={s.avatarText}>{profileInitial(profile)}</Text>
                </View>
                <View style={s.profileResultText}>
                  <Text style={s.author}>{profile.publicName}</Text>
                  <Text style={s.mini}>{profile.statusText || profile.bio}</Text>
                </View>
                <Text style={s.chevron}>›</Text>
              </Pressable>
            ))}
          </View>
        </View>
      </Modal>

      <Modal
        visible={Boolean(profileOpen) || profileLoading}
        transparent
        animationType="fade"
        onRequestClose={() => { setProfileOpen(null); setProfileLoading(false); }}
      >
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            {profileLoading && !profileOpen ? (
              <ActivityIndicator style={s.profileLoader} />
            ) : profileOpen ? (
              <>
                <View style={s.modalHeader}>
                  <View style={s.profileIdentity}>
                    <View style={[s.avatar, profileOpen.role === "DEV" && s.avatarDev]}>
                      <Text style={s.avatarText}>{profileInitial(profileOpen)}</Text>
                    </View>
                    <View style={s.profileIdentityText}>
                      <View style={s.nameRow}>
                        <Text style={s.modalTitle}>{profileOpen.publicName}</Text>
                        {profileOpen.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                      </View>
                      <Text style={s.mini}>{profileOpen.statusText || "Perfil GRUPO LUA"}</Text>
                    </View>
                  </View>
                  <Pressable onPress={() => setProfileOpen(null)}><Text style={s.modalClose}>✕</Text></Pressable>
                </View>
                {profileOpen.bio ? <Text style={s.profileBio}>{profileOpen.bio}</Text> : null}
                <Text style={s.profileCounts}>{profileCounts.posts} post(s) • {profileCounts.favorites} favorito(s)</Text>
                <View style={s.tabRow}>
                  <Pressable style={[s.tab, profileTab === "POSTS" && s.tabActive]} onPress={() => setProfileTab("POSTS")}>
                    <Text style={[s.tabText, profileTab === "POSTS" && s.tabTextActive]}>POSTS</Text>
                  </Pressable>
                  <Pressable style={[s.tab, profileTab === "FAVORITES" && s.tabActive]} onPress={() => setProfileTab("FAVORITES")}>
                    <Text style={[s.tabText, profileTab === "FAVORITES" && s.tabTextActive]}>FAVORITOS</Text>
                  </Pressable>
                </View>
                {currentProfilePosts.length === 0 ? (
                  <Text style={s.noComments}>Nada nesta aba.</Text>
                ) : currentProfilePosts.slice(0, 20).map((post) => (
                  <View key={post.id} style={s.profilePost}>
                    <Text style={s.profilePostTitle}>{post.item.title}</Text>
                    <Text numberOfLines={3} style={s.profilePostPreview}>{post.item.content}</Text>
                    <Text style={s.mini}>{dateText(post.createdAt)} • ♥ {post.reactions.likeCount} • ★ {post.reactions.favoriteCount}</Text>
                  </View>
                ))}
              </>
            ) : null}
          </View>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  topBar: { minHeight: 48, flexDirection: "row", alignItems: "center", gap: 8, marginBottom: 10 },
  topSpacer: { flex: 1 },
  topIcon: {
    width: 42,
    height: 42,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(5,5,7,0.24)",
    alignItems: "center",
    justifyContent: "center",
    position: "relative"
  },
  profileGlyph: { width: 22, height: 22, alignItems: "center", justifyContent: "flex-end" },
  profileHead: { width: 8, height: 8, borderRadius: 4, borderWidth: 1.4, borderColor: "#FFFFFF", position: "absolute", top: 1 },
  profileShoulders: { width: 18, height: 9, borderTopLeftRadius: 9, borderTopRightRadius: 9, borderWidth: 1.4, borderBottomWidth: 0, borderColor: "#FFFFFF" },
  chatIcon: { color: "#FFFFFF", fontSize: 18 },
  notificationIcon: { color: "#FFFFFF", fontSize: 21, marginTop: -2 },
  counterBadge: {
    position: "absolute",
    right: -4,
    top: -5,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: "#D22730",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 4
  },
  counterBadgeText: { color: "#FFFFFF", fontSize: 7, fontWeight: "900" },
  search: {
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.17)",
    backgroundColor: "rgba(5,5,7,0.28)",
    color: "#FFFFFF",
    paddingHorizontal: 13
  },
  searchLoader: { marginVertical: 7 },
  searchResults: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(6,6,8,0.68)",
    marginTop: 6,
    overflow: "hidden"
  },
  profileResult: {
    flexDirection: "row",
    alignItems: "center",
    gap: 10,
    paddingVertical: 10,
    paddingHorizontal: 9,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "rgba(255,255,255,0.12)"
  },
  profileResultText: { flex: 1 },
  avatarSmall: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.28)",
    backgroundColor: "rgba(0,0,0,0.28)",
    alignItems: "center",
    justifyContent: "center"
  },
  avatarDev: { borderColor: "#D8454D", borderWidth: 2 },
  avatarText: { color: "#FFFFFF", fontWeight: "900" },
  nameRow: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  author: { color: "#FFFFFF", fontWeight: "900", fontSize: 12 },
  devBadge: {
    color: "#FF9A9F",
    fontWeight: "900",
    fontSize: 7,
    borderRadius: 5,
    backgroundColor: "rgba(125,14,20,0.56)",
    paddingHorizontal: 5,
    paddingVertical: 2
  },
  chevron: { color: "rgba(235,235,240,0.55)", fontSize: 20 },
  mini: { color: "rgba(225,225,232,0.58)", fontSize: 8, marginTop: 3 },
  messageBox: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.13)",
    backgroundColor: "rgba(5,5,7,0.30)",
    padding: 10,
    marginTop: 8
  },
  message: { color: "#E6D8E8", fontSize: 10 },
  loader: { marginVertical: 28 },
  empty: {
    marginTop: 14,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.15)",
    backgroundColor: "rgba(5,5,7,0.28)",
    padding: 24,
    alignItems: "center"
  },
  emptyTitle: { color: "#FFFFFF", fontSize: 16, fontWeight: "900" },
  emptyText: { color: "rgba(235,235,240,0.68)", fontSize: 10, lineHeight: 16, textAlign: "center", marginTop: 6 },
  post: {
    marginTop: 11,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.14)",
    backgroundColor: "rgba(5,5,7,0.32)",
    padding: 13
  },
  pinnedPost: { borderColor: "rgba(222,66,74,0.54)" },
  pinnedTag: { color: "#FF858B", fontSize: 7, fontWeight: "900", letterSpacing: 0.8, marginBottom: 9 },
  postHeader: { flexDirection: "row", alignItems: "center", gap: 9 },
  avatar: {
    width: 38,
    height: 38,
    borderRadius: 20,
    backgroundColor: "rgba(0,0,0,0.28)",
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.25)",
    alignItems: "center",
    justifyContent: "center"
  },
  postIdentity: { flex: 1 },
  meta: { color: "rgba(225,225,232,0.56)", fontSize: 8, marginTop: 2 },
  kind: {
    color: "#E1C0F5",
    fontWeight: "900",
    fontSize: 7,
    borderWidth: 1,
    borderColor: "rgba(224,190,245,0.35)",
    backgroundColor: "rgba(54,25,69,0.34)",
    borderRadius: 8,
    paddingHorizontal: 7,
    paddingVertical: 5
  },
  postComment: { color: "#F0EDF2", fontSize: 11, lineHeight: 17, marginTop: 11 },
  postTitle: { color: "#FFFFFF", fontSize: 15, fontWeight: "900", marginTop: 12 },
  codeBox: {
    marginTop: 8,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.13)",
    backgroundColor: "rgba(0,0,0,0.30)",
    padding: 11
  },
  code: { color: "#E2E2E7", fontFamily: "monospace", fontSize: 9, lineHeight: 14 },
  previewNote: { color: "rgba(225,225,232,0.55)", fontSize: 8, lineHeight: 13, marginTop: 6 },
  reactionRow: { flexDirection: "row", alignItems: "center", gap: 10, marginTop: 11 },
  reaction: { flexDirection: "row", alignItems: "center", gap: 4, minHeight: 34 },
  reactionIcon: { color: "#FFFFFF", fontSize: 20 },
  reactionIconActive: { color: "#FF5F68" },
  favoriteActive: { color: "#F1D275" },
  commentGlyph: { color: "#FFFFFF", fontSize: 22, marginTop: -2 },
  reactionCount: { color: "rgba(245,245,248,0.82)", fontSize: 8, fontWeight: "800" },
  reactionSpacer: { flex: 1 },
  copyButton: {
    minHeight: 32,
    borderRadius: 9,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.15)",
    backgroundColor: "rgba(0,0,0,0.20)",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 10
  },
  copyText: { color: "rgba(245,245,248,0.80)", fontSize: 7, fontWeight: "900" },
  secondaryRow: { flexDirection: "row", alignItems: "center", gap: 14, marginTop: 5 },
  secondaryText: { color: "rgba(225,225,232,0.58)", fontSize: 8 },
  devAction: { color: "#FF848A", fontSize: 8, fontWeight: "800" },
  commentsBox: { borderTopWidth: 1, borderTopColor: "rgba(255,255,255,0.12)", marginTop: 11, paddingTop: 8 },
  commentLoader: { marginVertical: 10 },
  noComments: { color: "rgba(225,225,232,0.58)", fontSize: 10, textAlign: "center", marginVertical: 13 },
  comment: { borderRadius: 11, backgroundColor: "rgba(0,0,0,0.22)", padding: 9, marginTop: 6 },
  reply: { marginLeft: 18, borderLeftWidth: 2, borderLeftColor: "rgba(181,127,216,0.55)" },
  commentHead: { flexDirection: "row", justifyContent: "space-between", gap: 8 },
  commentAuthor: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  commentText: { color: "#E7E7EB", fontSize: 10, lineHeight: 15, marginTop: 5 },
  commentActions: { flexDirection: "row", gap: 12, marginTop: 6 },
  commentActionText: { color: "#C8A8DC", fontSize: 7, fontWeight: "900" },
  deleteText: { color: "#FF7C82", fontSize: 7, fontWeight: "900" },
  replying: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
    borderRadius: 8,
    backgroundColor: "rgba(54,25,69,0.38)",
    padding: 8,
    marginTop: 8
  },
  replyingText: { color: "#DFC8ED", fontSize: 8 },
  cancelReply: { color: "#D0D0D5", fontSize: 12 },
  commentComposer: { flexDirection: "row", alignItems: "flex-end", gap: 7, marginTop: 8 },
  commentInput: {
    flex: 1,
    minHeight: 44,
    maxHeight: 120,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.16)",
    backgroundColor: "rgba(0,0,0,0.25)",
    color: "#FFFFFF",
    paddingHorizontal: 10,
    paddingVertical: 9
  },
  commentSend: {
    minWidth: 62,
    minHeight: 44,
    borderRadius: 10,
    backgroundColor: "#FFFFFF",
    alignItems: "center",
    justifyContent: "center",
    paddingHorizontal: 7
  },
  commentSendText: { color: "#050505", fontSize: 7, fontWeight: "900" },
  disabled: { opacity: 0.42 },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.68)", alignItems: "center", justifyContent: "center", padding: 16 },
  modalBox: {
    width: "100%",
    maxWidth: 540,
    maxHeight: "88%",
    borderRadius: 20,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.18)",
    backgroundColor: "rgba(8,8,10,0.88)",
    padding: 15
  },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  modalTitle: { color: "#FFFFFF", fontSize: 17, fontWeight: "900" },
  modalClose: { color: "#D0D0D5", fontSize: 18, padding: 5 },
  tabRow: { flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 12 },
  tab: {
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "rgba(255,255,255,0.17)",
    backgroundColor: "rgba(0,0,0,0.20)",
    paddingHorizontal: 9,
    paddingVertical: 7
  },
  tabActive: { backgroundColor: "#FFFFFF", borderColor: "#FFFFFF" },
  tabText: { color: "rgba(235,235,240,0.64)", fontSize: 7, fontWeight: "900" },
  tabTextActive: { color: "#050505" },
  readAll: { alignSelf: "flex-end", marginTop: 9, paddingVertical: 6 },
  readAllText: { color: "#D3B7E4", fontSize: 7, fontWeight: "900" },
  notice: { borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", padding: 10, marginTop: 7 },
  noticeUnread: { borderColor: "rgba(199,145,231,0.45)", backgroundColor: "rgba(47,25,58,0.36)" },
  noticeText: { color: "#EFEFF2", fontSize: 10, lineHeight: 15 },
  profileLoader: { marginVertical: 30 },
  profileIdentity: { flexDirection: "row", alignItems: "center", gap: 10, flex: 1 },
  profileIdentityText: { flex: 1 },
  profileBio: { color: "rgba(235,235,240,0.72)", fontSize: 10, lineHeight: 16, marginTop: 10 },
  profileCounts: { color: "#D9BCEB", fontSize: 9, fontWeight: "900", marginTop: 10 },
  profilePost: { borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(0,0,0,0.18)", padding: 9, marginTop: 8 },
  profilePostTitle: { color: "#FFFFFF", fontSize: 10, fontWeight: "900" },
  profilePostPreview: { color: "rgba(235,235,240,0.68)", fontFamily: "monospace", fontSize: 8, lineHeight: 12, marginTop: 5 }
});
