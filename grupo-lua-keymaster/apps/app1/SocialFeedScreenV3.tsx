import { useEffect, useMemo, useRef, useState } from "react";
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
  createGlobalAnnouncement,
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

function dateText(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function notificationText(item: SocialNotification) {
  const who = item.actor?.publicName || "GRUPO LUA";
  if (item.kind === "LIKE") return `${who} curtiu sua publicação.`;
  if (item.kind === "COMMENT") return `${who} comentou ou respondeu sua publicação.`;
  if (item.kind === "FAVORITE") return `${who} favoritou sua publicação.`;
  return "Nova mensagem global do GRUPO LUA.";
}

function profileInitial(profile?: { publicName?: string | null }) {
  return String(profile?.publicName || "L").slice(0, 1).toUpperCase();
}

export function SocialFeedScreen({
  sessionToken,
  deviceToken,
  viewerRole = "ADM"
}: {
  sessionToken: string;
  deviceToken: string;
  viewerRole?: App1Role;
}) {
  const [posts, setPosts] = useState<SocialPost[]>([]);
  const [announcements, setAnnouncements] = useState<Array<{ id: string; text: string; createdAt: string; expiresAt: string; author: { profileId: string | null; publicName: string; role: "DEV" } }>>([]);
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
  const [unread, setUnread] = useState<Record<"ALL" | SocialNotificationKind, number>>({ ALL: 0, LIKE: 0, COMMENT: 0, FAVORITE: 0, ANNOUNCEMENT: 0 });
  const [announcementOpen, setAnnouncementOpen] = useState(false);
  const [announcementDraft, setAnnouncementDraft] = useState("");
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
      setAnnouncements(feed.announcements);
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
    const action = `like:${post.id}`;
    if (busyAction) return;
    setBusyAction(action);
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
    const action = `favorite:${post.id}`;
    if (busyAction) return;
    setBusyAction(action);
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
    if (!commentDraft.trim() || busyAction) return;
    setBusyAction(`comment:${post.id}`);
    const text = commentDraft.trim();
    setCommentDraft("");
    try {
      const result = await createSocialComment(sessionToken, deviceToken, post.id, text, replyTo?.id || null);
      if (!mounted.current) return;
      setComments((current) => ({
        ...current,
        [post.id]: [...(current[post.id] || []), result.comment]
      }));
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
            setComments((current) => ({ ...current, [post.id]: (current[post.id] || []).filter((item) => !ids.has(item.id)) }));
            patchPost(post.id, (current) => ({ ...current, reactions: { ...current.reactions, commentCount: Math.max(0, current.reactions.commentCount - ids.size) } }));
          } catch (error) {
            if (mounted.current) Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível apagar.");
          } finally {
            if (mounted.current) setBusyAction(null);
          }
        }
      }
    ]);
  }

  async function copyPost(post: SocialPost) {
    if (busyAction) return;
    setBusyAction(`copy:${post.id}`);
    try {
      let content = post.item.content;
      if (post.item.truncated) content = (await getSocialPost(sessionToken, deviceToken, post.id)).post.item.content;
      await Clipboard.setStringAsync(content);
      if (mounted.current) setMessage(`${post.item.title} copiado por completo.`);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao copiar", error instanceof Error ? error.message : "Não foi possível copiar.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
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
      if (!mounted.current) return;
      await reload(false);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao fixar", error instanceof Error ? error.message : "A publicação não pôde ser fixada.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  async function openProfile(profile: PublicProfileView | SocialPost["author"]) {
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
      await markSocialNotificationsRead(sessionToken, deviceToken, notificationKind === "ALL" ? {} : { kind: notificationKind });
      if (!mounted.current) return;
      await changeNotificationKind(notificationKind);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha", error instanceof Error ? error.message : "Não foi possível marcar como lidas.");
    }
  }

  async function publishAnnouncement() {
    if (viewerRole !== "DEV" || !announcementDraft.trim() || busyAction) return;
    setBusyAction("announcement");
    try {
      await createGlobalAnnouncement(sessionToken, deviceToken, announcementDraft.trim());
      if (!mounted.current) return;
      setAnnouncementDraft("");
      setAnnouncementOpen(false);
      await reload(false);
      Alert.alert("Mensagem global publicada", "O anúncio DEV foi enviado e possui retenção de 24 horas.");
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao publicar", error instanceof Error ? error.message : "Não foi possível publicar o anúncio.");
    } finally {
      if (mounted.current) setBusyAction(null);
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
    return () => { cancelled = true; clearTimeout(timer); };
  }, [search, sessionToken, deviceToken]);

  const currentProfilePosts = profileTab === "POSTS" ? profilePosts : profileFavorites;
  const notificationTabs = useMemo<Array<{ key: "ALL" | SocialNotificationKind; label: string }>>(() => [
    { key: "ALL", label: "TODAS" },
    { key: "LIKE", label: "CURTIDAS" },
    { key: "COMMENT", label: "COMENTÁRIOS" },
    { key: "FAVORITE", label: "FAVORITOS" }
  ], []);

  return (
    <View style={s.root}>
      <View style={s.header}>
        <View style={{ flex: 1 }}>
          <Text style={s.title}>Social</Text>
          <Text style={s.subtitle}>Códigos, loadstrings, perfis e comunidade GRUPO LUA.</Text>
        </View>
        {viewerRole === "DEV" ? (
          <Pressable style={s.iconButton} onPress={() => setAnnouncementOpen(true)}><Text style={s.devIcon}>!</Text></Pressable>
        ) : null}
        <Pressable style={s.iconButton} onPress={openNotifications}>
          <Text style={s.iconText}>♢</Text>
          {unread.ALL > 0 ? <View style={s.counterBadge}><Text style={s.counterBadgeText}>{unread.ALL > 99 ? "99+" : unread.ALL}</Text></View> : null}
        </Pressable>
        <Pressable style={[s.iconButton, loading && s.disabled]} disabled={loading} onPress={() => reload(true)}><Text style={s.iconText}>↻</Text></Pressable>
      </View>

      <TextInput
        value={search}
        onChangeText={setSearch}
        style={s.search}
        placeholder="Buscar perfil por pseudônimo..."
        placeholderTextColor="#626269"
        autoCapitalize="none"
        autoCorrect={false}
      />
      {searching ? <ActivityIndicator style={{ marginVertical: 7 }} /> : null}
      {profiles.length > 0 ? (
        <View style={s.searchResults}>
          {profiles.map((profile) => (
            <Pressable key={profile.profileId || profile.publicName} style={s.profileResult} onPress={() => openProfile(profile)}>
              <View style={[s.avatarSmall, profile.role === "DEV" && s.avatarDev]}><Text style={s.avatarText}>{profileInitial(profile)}</Text></View>
              <View style={{ flex: 1 }}>
                <View style={s.nameRow}><Text style={s.author}>{profile.publicName}</Text>{profile.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}</View>
                <Text style={s.mini}>{profile.statusText || profile.bio || "Abrir perfil"}</Text>
              </View>
              <Text style={s.chevron}>›</Text>
            </Pressable>
          ))}
        </View>
      ) : null}

      {message ? <Text style={s.message}>{message}</Text> : null}
      {loading ? <ActivityIndicator style={{ marginVertical: 28 }} /> : null}

      {!loading && announcements.map((announcement) => (
        <View key={announcement.id} style={s.announcement}>
          <View style={s.nameRow}>
            <Text style={s.announcementTag}>DEV • MENSAGEM GLOBAL</Text>
            <Text style={s.mini}>{dateText(announcement.createdAt)}</Text>
          </View>
          <Text style={s.announcementText}>{announcement.text}</Text>
        </View>
      ))}

      {!loading && posts.length === 0 ? (
        <View style={s.empty}><Text style={s.emptyTitle}>Feed vazio</Text><Text style={s.emptyText}>Compartilhe um código ou loadstring pela aba Arquivos.</Text></View>
      ) : null}

      {!loading ? posts.map((post) => {
        const postComments = comments[post.id] || [];
        const isExpanded = expandedPostId === post.id;
        return (
          <View key={post.id} style={[s.post, post.pinned && s.pinnedPost]}>
            {post.pinned ? <Text style={s.pinnedTag}>FIXADO PELO GRUPO LUA</Text> : null}
            <View style={s.postHeader}>
              <Pressable style={[s.avatar, post.author.role === "DEV" && s.avatarDev]} onPress={() => openProfile(post.author)}>
                <Text style={s.avatarText}>{profileInitial(post.author)}</Text>
              </Pressable>
              <Pressable style={{ flex: 1 }} onPress={() => openProfile(post.author)}>
                <View style={s.nameRow}>
                  <Text style={s.author}>{post.author.publicName}</Text>
                  {post.author.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                </View>
                <Text style={s.meta}>{dateText(post.createdAt)} • expira {dateText(post.expiresAt)}</Text>
              </Pressable>
              <Text style={s.kind}>{post.kind === "CODE" ? "CÓDIGO" : "LOADSTRING"}</Text>
            </View>

            {post.comment ? <View style={s.postComment}><Text style={s.postCommentText}>{post.comment}</Text></View> : null}
            <Text style={s.postTitle}>{post.item.title}</Text>
            <View style={s.codeBox}><Text numberOfLines={8} style={s.code}>{post.item.content}</Text></View>
            {post.item.truncated ? <Text style={s.previewNote}>Prévia reduzida. Copiar baixa o conteúdo completo.</Text> : null}

            <View style={s.reactionRow}>
              <Pressable disabled={Boolean(busyAction)} style={[s.reaction, post.reactions.liked && s.reactionActive]} onPress={() => toggleLike(post)}>
                <Text style={s.reactionText}>{post.reactions.liked ? "♥" : "♡"} {post.reactions.likeCount}</Text>
              </Pressable>
              <Pressable style={[s.reaction, isExpanded && s.reactionActive]} onPress={() => openComments(post)}>
                <Text style={s.reactionText}>COMENTÁRIOS {post.reactions.commentCount}</Text>
              </Pressable>
              <Pressable disabled={Boolean(busyAction)} style={[s.reaction, post.reactions.favorited && s.reactionActive]} onPress={() => toggleFavorite(post)}>
                <Text style={s.reactionText}>{post.reactions.favorited ? "★" : "☆"} {post.reactions.favoriteCount}</Text>
              </Pressable>
            </View>

            <View style={s.secondaryRow}>
              <Pressable style={s.secondaryAction} disabled={Boolean(busyAction)} onPress={() => copyPost(post)}><Text style={s.secondaryText}>COPIAR</Text></Pressable>
              {post.reactions.favoriteCount > 0 ? <Pressable style={s.secondaryAction} onPress={() => showFavorites(post)}><Text style={s.secondaryText}>QUEM FAVORITOU</Text></Pressable> : null}
              {viewerRole === "DEV" ? <Pressable style={s.secondaryAction} disabled={Boolean(busyAction)} onPress={() => togglePin(post)}><Text style={[s.secondaryText, s.devAction]}>{post.pinned ? "DESAFIXAR" : "FIXAR"}</Text></Pressable> : null}
            </View>

            {isExpanded ? (
              <View style={s.commentsBox}>
                {commentsLoading === post.id ? <ActivityIndicator style={{ marginVertical: 10 }} /> : postComments.length === 0 ? <Text style={s.noComments}>Nenhum comentário ainda.</Text> : postComments.map((comment) => (
                  <View key={comment.id} style={[s.comment, comment.parentCommentId && s.reply]}>
                    <View style={s.commentHead}>
                      <Pressable onPress={() => openProfile(comment.author)} style={s.nameRow}>
                        <Text style={s.commentAuthor}>{comment.author.publicName}</Text>
                        {comment.author.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}
                      </Pressable>
                      <Text style={s.mini}>{dateText(comment.createdAt)}</Text>
                    </View>
                    <Text style={s.commentText}>{comment.text}</Text>
                    <View style={s.commentActions}>
                      <Pressable onPress={() => { setReplyTo(comment); setCommentDraft(`@${comment.author.publicName} `); }}><Text style={s.commentActionText}>RESPONDER</Text></Pressable>
                      {comment.mine ? <Pressable onPress={() => confirmDeleteComment(post, comment)}><Text style={[s.commentActionText, s.deleteText]}>APAGAR</Text></Pressable> : null}
                    </View>
                  </View>
                ))}
                {replyTo ? <View style={s.replying}><Text style={s.replyingText}>Respondendo a {replyTo.author.publicName}</Text><Pressable onPress={() => { setReplyTo(null); setCommentDraft(""); }}><Text style={s.cancelReply}>✕</Text></Pressable></View> : null}
                <View style={s.commentComposer}>
                  <TextInput value={commentDraft} onChangeText={setCommentDraft} maxLength={1000} multiline editable={!busyAction} style={s.commentInput} placeholder="Escreva um comentário..." placeholderTextColor="#666" />
                  <Pressable disabled={!commentDraft.trim() || Boolean(busyAction)} style={[s.commentSend, (!commentDraft.trim() || busyAction) && s.disabled]} onPress={() => submitComment(post)}><Text style={s.commentSendText}>ENVIAR</Text></Pressable>
                </View>
              </View>
            ) : null}
          </View>
        );
      }) : null}

      <Modal visible={notificationsOpen} transparent animationType="fade" onRequestClose={() => setNotificationsOpen(false)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            <View style={s.modalHeader}><Text style={s.modalTitle}>Notificações Social</Text><Pressable onPress={() => setNotificationsOpen(false)}><Text style={s.modalClose}>✕</Text></Pressable></View>
            <View style={s.tabRow}>
              {notificationTabs.map((tab) => <Pressable key={tab.key} style={[s.tab, notificationKind === tab.key && s.tabActive]} onPress={() => changeNotificationKind(tab.key)}><Text style={[s.tabText, notificationKind === tab.key && s.tabTextActive]}>{tab.label}</Text></Pressable>)}
            </View>
            <Pressable style={s.readAll} onPress={readNotifications}><Text style={s.readAllText}>MARCAR COMO LIDAS</Text></Pressable>
            {notifications.length === 0 ? <Text style={s.noComments}>Nenhuma notificação nesta categoria.</Text> : notifications.map((notice) => (
              <Pressable key={notice.id} style={[s.notice, !notice.read && s.noticeUnread]} onPress={() => { if (notice.postId) { setNotificationsOpen(false); setExpandedPostId(notice.kind === "COMMENT" ? notice.postId : null); } }}>
                <Text style={s.noticeText}>{notificationText(notice)}</Text><Text style={s.mini}>{dateText(notice.createdAt)}{notice.postTitle ? ` • ${notice.postTitle}` : ""}</Text>
              </Pressable>
            ))}
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(favoritesOpen)} transparent animationType="fade" onRequestClose={() => setFavoritesOpen(null)}>
        <View style={s.modalBackdrop}><View style={s.modalBox}><View style={s.modalHeader}><Text style={s.modalTitle}>Quem favoritou</Text><Pressable onPress={() => setFavoritesOpen(null)}><Text style={s.modalClose}>✕</Text></Pressable></View>{(favoritesOpen || []).map((profile) => <Pressable key={profile.profileId || profile.publicName} style={s.profileResult} onPress={() => { setFavoritesOpen(null); openProfile(profile); }}><View style={[s.avatarSmall, profile.role === "DEV" && s.avatarDev]}><Text style={s.avatarText}>{profileInitial(profile)}</Text></View><View style={{ flex: 1 }}><Text style={s.author}>{profile.publicName}</Text><Text style={s.mini}>{profile.statusText || profile.bio}</Text></View><Text style={s.chevron}>›</Text></Pressable>)}</View></View>
      </Modal>

      <Modal visible={Boolean(profileOpen) || profileLoading} transparent animationType="fade" onRequestClose={() => { setProfileOpen(null); setProfileLoading(false); }}>
        <View style={s.modalBackdrop}>
          <View style={s.modalBox}>
            {profileLoading && !profileOpen ? <ActivityIndicator style={{ marginVertical: 30 }} /> : profileOpen ? (
              <>
                <View style={s.modalHeader}><View style={s.profileIdentity}><View style={[s.avatar, profileOpen.role === "DEV" && s.avatarDev]}><Text style={s.avatarText}>{profileInitial(profileOpen)}</Text></View><View><View style={s.nameRow}><Text style={s.modalTitle}>{profileOpen.publicName}</Text>{profileOpen.role === "DEV" ? <Text style={s.devBadge}>DEV</Text> : null}</View><Text style={s.mini}>{profileOpen.statusText || "Perfil GRUPO LUA"}</Text></View></View><Pressable onPress={() => setProfileOpen(null)}><Text style={s.modalClose}>✕</Text></Pressable></View>
                {profileOpen.bio ? <Text style={s.profileBio}>{profileOpen.bio}</Text> : null}
                <Text style={s.profileCounts}>{profileCounts.posts} post(s) • {profileCounts.favorites} favorito(s)</Text>
                <View style={s.tabRow}><Pressable style={[s.tab, profileTab === "POSTS" && s.tabActive]} onPress={() => setProfileTab("POSTS")}><Text style={[s.tabText, profileTab === "POSTS" && s.tabTextActive]}>POSTS</Text></Pressable><Pressable style={[s.tab, profileTab === "FAVORITES" && s.tabActive]} onPress={() => setProfileTab("FAVORITES")}><Text style={[s.tabText, profileTab === "FAVORITES" && s.tabTextActive]}>FAVORITOS</Text></Pressable></View>
                {currentProfilePosts.length === 0 ? <Text style={s.noComments}>Nada nesta aba.</Text> : currentProfilePosts.slice(0, 20).map((post) => <View key={post.id} style={s.profilePost}><Text style={s.profilePostTitle}>{post.item.title}</Text><Text numberOfLines={3} style={s.profilePostPreview}>{post.item.content}</Text><Text style={s.mini}>{dateText(post.createdAt)} • ♥ {post.reactions.likeCount} • ★ {post.reactions.favoriteCount}</Text></View>)}
              </>
            ) : null}
          </View>
        </View>
      </Modal>

      <Modal visible={announcementOpen} transparent animationType="fade" onRequestClose={() => { if (!busyAction) setAnnouncementOpen(false); }}>
        <View style={s.modalBackdrop}><View style={s.modalBox}><View style={s.modalHeader}><Text style={s.modalTitle}>Mensagem global DEV</Text><Pressable onPress={() => setAnnouncementOpen(false)}><Text style={s.modalClose}>✕</Text></Pressable></View><Text style={s.profileBio}>Mensagem oficial separada dos chats privados. O envio é validado e auditado pelo servidor.</Text><TextInput value={announcementDraft} onChangeText={setAnnouncementDraft} maxLength={1000} multiline editable={!busyAction} style={[s.commentInput, { minHeight: 120, marginTop: 12 }]} placeholder="Escreva o anúncio..." placeholderTextColor="#666" textAlignVertical="top" /><Pressable disabled={!announcementDraft.trim() || Boolean(busyAction)} style={[s.publishButton, (!announcementDraft.trim() || busyAction) && s.disabled]} onPress={publishAnnouncement}><Text style={s.publishText}>{busyAction === "announcement" ? "PUBLICANDO..." : "PUBLICAR PARA TODOS"}</Text></Pressable></View></View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1 },
  header: { flexDirection: "row", alignItems: "center", gap: 7, marginBottom: 8 },
  title: { color: "#FFF", fontSize: 22, fontWeight: "900" },
  subtitle: { color: "#74747C", fontSize: 10, marginTop: 3 },
  iconButton: { width: 42, height: 42, borderRadius: 13, borderWidth: 1, borderColor: "#2D2D34", alignItems: "center", justifyContent: "center", position: "relative" },
  iconText: { color: "#C4A6DA", fontSize: 18 },
  devIcon: { color: "#FF646B", fontSize: 16, fontWeight: "900" },
  counterBadge: { position: "absolute", right: -4, top: -5, minWidth: 18, height: 18, borderRadius: 9, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 4 },
  counterBadgeText: { color: "#050505", fontSize: 7, fontWeight: "900" },
  disabled: { opacity: 0.42 },
  search: { minHeight: 48, borderRadius: 13, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#0D0D10", color: "#FFF", paddingHorizontal: 13 },
  searchResults: { borderRadius: 14, borderWidth: 1, borderColor: "#29292F", backgroundColor: "#09090C", marginTop: 6, overflow: "hidden" },
  profileResult: { flexDirection: "row", alignItems: "center", gap: 10, paddingVertical: 10, paddingHorizontal: 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "#27272C" },
  avatarSmall: { width: 34, height: 34, borderRadius: 17, borderWidth: 1, borderColor: "#4A4A52", backgroundColor: "#151518", alignItems: "center", justifyContent: "center" },
  avatarDev: { borderColor: "#DB474F", borderWidth: 2 },
  avatarText: { color: "#FFF", fontWeight: "900" },
  nameRow: { flexDirection: "row", alignItems: "center", gap: 6, flexWrap: "wrap" },
  chevron: { color: "#75757C", fontSize: 20 },
  mini: { color: "#66666E", fontSize: 8, marginTop: 3 },
  message: { color: "#BCA4CF", fontSize: 10, marginTop: 8 },
  announcement: { borderRadius: 15, borderWidth: 1, borderColor: "#59252A", backgroundColor: "#13090B", padding: 13, marginTop: 10 },
  announcementTag: { color: "#FF686F", fontSize: 8, fontWeight: "900", marginRight: "auto" },
  announcementText: { color: "#F0E3E4", fontSize: 12, lineHeight: 18, marginTop: 7 },
  empty: { marginTop: 18, borderRadius: 18, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#09090C", padding: 26, alignItems: "center" },
  emptyTitle: { color: "#FFF", fontSize: 16, fontWeight: "900" },
  emptyText: { color: "#777780", fontSize: 11, lineHeight: 17, textAlign: "center", marginTop: 6 },
  post: { marginTop: 12, borderRadius: 18, borderWidth: 1, borderColor: "#25252B", backgroundColor: "#09090C", padding: 14 },
  pinnedPost: { borderColor: "#5A2C31" },
  pinnedTag: { color: "#FF656D", fontSize: 7, fontWeight: "900", letterSpacing: 0.8, marginBottom: 9 },
  postHeader: { flexDirection: "row", alignItems: "center", gap: 10 },
  avatar: { width: 38, height: 38, borderRadius: 20, backgroundColor: "#17121A", borderWidth: 1, borderColor: "#59436A", alignItems: "center", justifyContent: "center" },
  author: { color: "#FFF", fontWeight: "900", fontSize: 12 },
  devBadge: { color: "#FF686F", fontWeight: "900", fontSize: 7, borderRadius: 5, backgroundColor: "#22090B", paddingHorizontal: 5, paddingVertical: 2 },
  meta: { color: "#67676F", fontSize: 8, marginTop: 2 },
  kind: { color: "#B77BEE", fontWeight: "900", fontSize: 7, borderWidth: 1, borderColor: "#4C3165", borderRadius: 8, paddingHorizontal: 7, paddingVertical: 5 },
  postComment: { marginTop: 12, borderLeftWidth: 2, borderLeftColor: "#7D4AA7", paddingLeft: 10 },
  postCommentText: { color: "#D7D2DB", fontSize: 11, lineHeight: 17 },
  postTitle: { color: "#F2F2F4", fontSize: 15, fontWeight: "900", marginTop: 13 },
  codeBox: { marginTop: 9, borderRadius: 12, borderWidth: 1, borderColor: "#24242A", backgroundColor: "#050507", padding: 11 },
  code: { color: "#CACAD0", fontFamily: "monospace", fontSize: 9, lineHeight: 14 },
  previewNote: { color: "#777780", fontSize: 8, lineHeight: 13, marginTop: 6 },
  reactionRow: { flexDirection: "row", gap: 6, marginTop: 11 },
  reaction: { flex: 1, minHeight: 37, borderRadius: 9, borderWidth: 1, borderColor: "#303036", alignItems: "center", justifyContent: "center", paddingHorizontal: 5 },
  reactionActive: { borderColor: "#724B8F", backgroundColor: "#160D1E" },
  reactionText: { color: "#C7C7CD", fontSize: 7, fontWeight: "900" },
  secondaryRow: { flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 7 },
  secondaryAction: { borderRadius: 8, borderWidth: 1, borderColor: "#29292F", paddingHorizontal: 9, paddingVertical: 7 },
  secondaryText: { color: "#85858C", fontSize: 7, fontWeight: "900" },
  devAction: { color: "#EF6A70" },
  commentsBox: { borderTopWidth: 1, borderTopColor: "#25252B", marginTop: 12, paddingTop: 9 },
  noComments: { color: "#74747C", fontSize: 10, textAlign: "center", marginVertical: 13 },
  comment: { borderRadius: 10, backgroundColor: "#0E0E11", padding: 9, marginTop: 6 },
  reply: { marginLeft: 18, borderLeftWidth: 2, borderLeftColor: "#65447C" },
  commentHead: { flexDirection: "row", justifyContent: "space-between", gap: 8 },
  commentAuthor: { color: "#DCDCE0", fontSize: 9, fontWeight: "900" },
  commentText: { color: "#BEBEC5", fontSize: 10, lineHeight: 15, marginTop: 5 },
  commentActions: { flexDirection: "row", gap: 12, marginTop: 6 },
  commentActionText: { color: "#9174A8", fontSize: 7, fontWeight: "900" },
  deleteText: { color: "#CF6268" },
  replying: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", borderRadius: 8, backgroundColor: "#17101D", padding: 8, marginTop: 8 },
  replyingText: { color: "#BCA5CF", fontSize: 8 },
  cancelReply: { color: "#888890", fontSize: 12 },
  commentComposer: { flexDirection: "row", alignItems: "flex-end", gap: 7, marginTop: 8 },
  commentInput: { flex: 1, minHeight: 44, maxHeight: 120, borderRadius: 10, borderWidth: 1, borderColor: "#2B2B31", backgroundColor: "#0D0D10", color: "#FFF", paddingHorizontal: 10, paddingVertical: 9 },
  commentSend: { minWidth: 62, minHeight: 44, borderRadius: 10, backgroundColor: "#FFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 7 },
  commentSendText: { color: "#050505", fontSize: 7, fontWeight: "900" },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.86)", alignItems: "center", justifyContent: "center", padding: 16 },
  modalBox: { width: "100%", maxWidth: 540, maxHeight: "88%", borderRadius: 20, borderWidth: 1, borderColor: "#33333A", backgroundColor: "#09090C", padding: 15 },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  modalTitle: { color: "#FFF", fontSize: 17, fontWeight: "900" },
  modalClose: { color: "#A4A4AB", fontSize: 18, padding: 5 },
  tabRow: { flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 12 },
  tab: { borderRadius: 8, borderWidth: 1, borderColor: "#303036", paddingHorizontal: 9, paddingVertical: 7 },
  tabActive: { backgroundColor: "#FFF", borderColor: "#FFF" },
  tabText: { color: "#818189", fontSize: 7, fontWeight: "900" },
  tabTextActive: { color: "#050505" },
  readAll: { alignSelf: "flex-end", marginTop: 9, paddingVertical: 6 },
  readAllText: { color: "#A98AC0", fontSize: 7, fontWeight: "900" },
  notice: { borderRadius: 10, borderWidth: 1, borderColor: "#24242A", padding: 10, marginTop: 7 },
  noticeUnread: { borderColor: "#5B3E6F", backgroundColor: "#120D16" },
  noticeText: { color: "#D4D4D9", fontSize: 10, lineHeight: 15 },
  profileIdentity: { flexDirection: "row", alignItems: "center", gap: 10, flex: 1 },
  profileBio: { color: "#96969E", fontSize: 10, lineHeight: 16, marginTop: 10 },
  profileCounts: { color: "#B69AC9", fontSize: 9, fontWeight: "900", marginTop: 10 },
  profilePost: { borderRadius: 10, borderWidth: 1, borderColor: "#27272D", padding: 9, marginTop: 8 },
  profilePostTitle: { color: "#EAEAEC", fontSize: 10, fontWeight: "900" },
  profilePostPreview: { color: "#8B8B92", fontFamily: "monospace", fontSize: 8, lineHeight: 12, marginTop: 5 },
  publishButton: { minHeight: 48, borderRadius: 11, backgroundColor: "#3A1115", borderWidth: 1, borderColor: "#692329", alignItems: "center", justifyContent: "center", marginTop: 12 },
  publishText: { color: "#FF7A80", fontSize: 9, fontWeight: "900" }
});
