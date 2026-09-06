import { useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import * as Clipboard from "expo-clipboard";
import * as DocumentPicker from "expo-document-picker";
import type { App1Role } from "./api";
import {
  type PublicProfileView,
  type SocialAnnouncement,
  type SocialComment,
  type SocialNotification,
  type SocialPost,
  createSocialComment,
  deleteSocialComment,
  getOwnProfile,
  getProfileFavorites,
  getProfilePosts,
  getPublicProfile,
  getSocialPost,
  listSocialComments,
  listSocialFeed,
  listSocialNotifications,
  markSocialNotificationsRead,
  searchPublicProfiles,
  setSocialFavorite,
  setSocialLike,
  setSocialPostPinned
} from "./social-api";
import {
  type SocialStatusProfile,
  deleteSocialStatus,
  listSocialStatuses,
  socialStatusImageSource,
  uploadSocialStatus
} from "./social-status-api";

type MainTab = "FEED" | "PROFILE";
type ProfileTab = "POSTS" | "FAVORITES";

type ProfileBundle = {
  profile: PublicProfileView;
  posts: SocialPost[];
  favorites: SocialPost[];
  counts: { posts: number; favorites: number };
};

function shortDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("pt-BR");
}

function fullDate(value?: string | null) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

function relativeDate(value?: string | null) {
  if (!value) return "agora";
  const time = new Date(value).getTime();
  if (!Number.isFinite(time)) return "agora";
  const seconds = Math.max(0, Math.floor((Date.now() - time) / 1000));
  if (seconds < 60) return "agora";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} h`;
  return `${Math.floor(seconds / 86400)} d`;
}

function profileInitial(name?: string | null) {
  return String(name || "L").trim().slice(0, 1).toUpperCase() || "L";
}

function avatarGlyph(style?: string | null) {
  if (style === "CAT") return "ฅ";
  if (style === "CODE") return "</>";
  if (style === "GHOST") return "◌";
  return "☾";
}

function roleText(role: App1Role) {
  return role === "DEV" ? "DEV" : "ADM";
}

function notificationText(item: SocialNotification) {
  const who = item.actor?.publicName || "GRUPO LUA";
  if (item.kind === "LIKE") return `${who} curtiu sua publicação.`;
  if (item.kind === "COMMENT") return `${who} comentou sua publicação.`;
  if (item.kind === "FAVORITE") return `${who} favoritou sua publicação.`;
  return "Novo aviso dos desenvolvedores.";
}

function mimeFromAsset(asset: DocumentPicker.DocumentPickerAsset) {
  const declared = String(asset.mimeType || "").toLowerCase();
  if (["image/jpeg", "image/png", "image/webp"].includes(declared)) return declared;
  const name = String(asset.name || "").toLowerCase();
  if (name.endsWith(".png")) return "image/png";
  if (name.endsWith(".webp")) return "image/webp";
  if (name.endsWith(".jpg") || name.endsWith(".jpeg")) return "image/jpeg";
  return "";
}

function Avatar({
  name,
  avatarStyle,
  imageSource,
  size = 44,
  highlighted = false
}: {
  name: string;
  avatarStyle?: string | null;
  imageSource?: { uri: string; headers?: Record<string, string> } | null;
  size?: number;
  highlighted?: boolean;
}) {
  return (
    <View
      style={[
        s.avatar,
        { width: size, height: size, borderRadius: size / 2 },
        highlighted && s.avatarHighlighted
      ]}
    >
      {imageSource ? (
        <Image
          source={imageSource}
          style={{ width: size - 6, height: size - 6, borderRadius: (size - 6) / 2 }}
          resizeMode="cover"
        />
      ) : (
        <Text style={[s.avatarGlyph, avatarStyle === "CODE" && s.avatarCode]}>
          {avatarStyle ? avatarGlyph(avatarStyle) : profileInitial(name)}
        </Text>
      )}
    </View>
  );
}

type SocialIconName =
  | "bell"
  | "chat"
  | "search"
  | "heart"
  | "favorite"
  | "more"
  | "plus"
  | "eye"
  | "profile"
  | "trash"
  | "notice"
  | "close"
  | "chevron";

function SocialIcon({
  name,
  size = 24,
  color = "#FFFFFF",
  active = false
}: {
  name: SocialIconName;
  size?: number;
  color?: string;
  active?: boolean;
}) {
  const k = size / 24;
  const stroke = Math.max(1.35, 1.65 * k);
  const tint = active && (name === "heart" || name === "favorite") ? "#FF2638" : color;
  const box = [s.iconBox, { width: size, height: size }];

  if (name === "bell") {
    return (
      <View style={box}>
        <View style={{
          position: "absolute",
          left: 5 * k,
          top: 4 * k,
          width: 14 * k,
          height: 14 * k,
          borderWidth: stroke,
          borderColor: tint,
          borderTopLeftRadius: 8 * k,
          borderTopRightRadius: 8 * k,
          borderBottomLeftRadius: 4 * k,
          borderBottomRightRadius: 4 * k
        }} />
        <View style={{ position: "absolute", left: 10 * k, top: 1.8 * k, width: 4 * k, height: 3 * k, borderRadius: 2 * k, backgroundColor: tint }} />
        <View style={{ position: "absolute", left: 9.7 * k, top: 19 * k, width: 4.6 * k, height: 2.3 * k, borderRadius: 2 * k, backgroundColor: tint }} />
      </View>
    );
  }

  if (name === "chat") {
    return (
      <View style={box}>
        <View style={{
          position: "absolute",
          left: 3 * k,
          top: 3 * k,
          width: 18 * k,
          height: 14 * k,
          borderWidth: stroke,
          borderColor: tint,
          borderRadius: 5 * k
        }} />
        <View style={{
          position: "absolute",
          left: 6 * k,
          top: 15 * k,
          width: 6 * k,
          height: 6 * k,
          borderLeftWidth: stroke,
          borderBottomWidth: stroke,
          borderColor: tint,
          transform: [{ rotate: "-28deg" }]
        }} />
      </View>
    );
  }

  if (name === "search") {
    return (
      <View style={box}>
        <View style={{
          position: "absolute",
          left: 3 * k,
          top: 3 * k,
          width: 13 * k,
          height: 13 * k,
          borderRadius: 7 * k,
          borderWidth: stroke,
          borderColor: tint
        }} />
        <View style={{
          position: "absolute",
          left: 14 * k,
          top: 15 * k,
          width: 8 * k,
          height: stroke,
          borderRadius: stroke / 2,
          backgroundColor: tint,
          transform: [{ rotate: "45deg" }]
        }} />
      </View>
    );
  }

  if (name === "heart") {
    const fill = active ? tint : "transparent";
    return (
      <View style={box}>
        <View style={{
          position: "absolute",
          left: 6.3 * k,
          top: 7.4 * k,
          width: 11.4 * k,
          height: 11.4 * k,
          borderWidth: stroke,
          borderColor: tint,
          backgroundColor: fill,
          transform: [{ rotate: "45deg" }]
        }} />
        <View style={{
          position: "absolute",
          left: 4.1 * k,
          top: 4.2 * k,
          width: 10.8 * k,
          height: 10.8 * k,
          borderRadius: 6 * k,
          borderWidth: stroke,
          borderColor: tint,
          backgroundColor: fill
        }} />
        <View style={{
          position: "absolute",
          right: 4.1 * k,
          top: 4.2 * k,
          width: 10.8 * k,
          height: 10.8 * k,
          borderRadius: 6 * k,
          borderWidth: stroke,
          borderColor: tint,
          backgroundColor: fill
        }} />
      </View>
    );
  }

  if (name === "favorite") {
    return (
      <View style={box}>
        <View style={{
          position: "absolute",
          left: 2 * k,
          top: 8.2 * k,
          width: 0,
          height: 0,
          borderLeftWidth: 10 * k,
          borderRightWidth: 10 * k,
          borderBottomWidth: 7 * k,
          borderLeftColor: "transparent",
          borderRightColor: "transparent",
          borderBottomColor: tint,
          transform: [{ rotate: "35deg" }]
        }} />
        <View style={{
          position: "absolute",
          left: 8.8 * k,
          top: 2.2 * k,
          width: 0,
          height: 0,
          borderLeftWidth: 3.2 * k,
          borderRightWidth: 3.2 * k,
          borderBottomWidth: 8.6 * k,
          borderLeftColor: "transparent",
          borderRightColor: "transparent",
          borderBottomColor: tint,
          transform: [{ rotate: "-35deg" }]
        }} />
        <View style={{
          position: "absolute",
          left: 2 * k,
          top: 8.2 * k,
          width: 0,
          height: 0,
          borderLeftWidth: 10 * k,
          borderRightWidth: 10 * k,
          borderBottomWidth: 7 * k,
          borderLeftColor: "transparent",
          borderRightColor: "transparent",
          borderBottomColor: tint,
          transform: [{ rotate: "-35deg" }]
        }} />
      </View>
    );
  }

  if (name === "more") {
    return (
      <View style={box}>
        {[5, 11, 17].map((top) => (
          <View key={top} style={{ position: "absolute", top: top * k, width: 3 * k, height: 3 * k, borderRadius: 1.5 * k, backgroundColor: tint }} />
        ))}
      </View>
    );
  }

  if (name === "plus") {
    return (
      <View style={box}>
        <View style={{ position: "absolute", width: 15 * k, height: stroke, borderRadius: stroke / 2, backgroundColor: tint }} />
        <View style={{ position: "absolute", width: stroke, height: 15 * k, borderRadius: stroke / 2, backgroundColor: tint }} />
      </View>
    );
  }

  if (name === "eye") {
    return (
      <View style={box}>
        <View style={{ width: 20 * k, height: 12 * k, borderRadius: 10 * k, borderWidth: stroke, borderColor: tint, alignItems: "center", justifyContent: "center" }}>
          <View style={{ width: 5.5 * k, height: 5.5 * k, borderRadius: 3 * k, backgroundColor: tint }} />
        </View>
      </View>
    );
  }

  if (name === "profile") {
    return (
      <View style={box}>
        <View style={{ position: "absolute", top: 3 * k, width: 8 * k, height: 8 * k, borderRadius: 4 * k, borderWidth: stroke, borderColor: tint }} />
        <View style={{
          position: "absolute",
          bottom: 3 * k,
          width: 18 * k,
          height: 9 * k,
          borderTopLeftRadius: 9 * k,
          borderTopRightRadius: 9 * k,
          borderWidth: stroke,
          borderBottomWidth: 0,
          borderColor: tint
        }} />
      </View>
    );
  }

  if (name === "trash") {
    return (
      <View style={box}>
        <View style={{ position: "absolute", top: 5 * k, width: 15 * k, height: stroke, borderRadius: stroke / 2, backgroundColor: tint }} />
        <View style={{ position: "absolute", top: 2.5 * k, width: 7 * k, height: 3 * k, borderWidth: stroke, borderBottomWidth: 0, borderColor: tint, borderTopLeftRadius: 2 * k, borderTopRightRadius: 2 * k }} />
        <View style={{ position: "absolute", top: 8 * k, width: 13 * k, height: 13 * k, borderWidth: stroke, borderTopWidth: 0, borderColor: tint, borderBottomLeftRadius: 3 * k, borderBottomRightRadius: 3 * k }} />
      </View>
    );
  }

  if (name === "notice") {
    return (
      <View style={box}>
        <View style={{ width: 20 * k, height: 20 * k, borderRadius: 10 * k, borderWidth: stroke, borderColor: tint, alignItems: "center", justifyContent: "center" }}>
          <View style={{ width: stroke, height: 8 * k, borderRadius: stroke / 2, backgroundColor: tint, marginBottom: 2 * k }} />
          <View style={{ width: 2.5 * k, height: 2.5 * k, borderRadius: 1.3 * k, backgroundColor: tint }} />
        </View>
      </View>
    );
  }

  if (name === "close") {
    return (
      <View style={box}>
        <View style={{ position: "absolute", width: 16 * k, height: stroke, borderRadius: stroke / 2, backgroundColor: tint, transform: [{ rotate: "45deg" }] }} />
        <View style={{ position: "absolute", width: 16 * k, height: stroke, borderRadius: stroke / 2, backgroundColor: tint, transform: [{ rotate: "-45deg" }] }} />
      </View>
    );
  }

  return (
    <View style={box}>
      <View style={{ position: "absolute", width: 9 * k, height: stroke, backgroundColor: tint, transform: [{ rotate: "45deg" }], top: 7 * k, left: 8 * k }} />
      <View style={{ position: "absolute", width: 9 * k, height: stroke, backgroundColor: tint, transform: [{ rotate: "-45deg" }], top: 13 * k, left: 8 * k }} />
    </View>
  );
}

export function SocialFeedScreenV5({
  sessionToken,
  deviceToken,
  viewerProfileId,
  viewerPublicName,
  viewerRole,
  sessionExpiresAt,
  onOpenChat,
  onOpenProfile
}: {
  sessionToken: string;
  deviceToken: string;
  viewerProfileId: string | null;
  viewerPublicName: string;
  viewerRole: App1Role;
  sessionExpiresAt: string;
  onOpenChat: () => void;
  onOpenProfile: () => void;
}) {
  const [mainTab, setMainTab] = useState<MainTab>("FEED");
  const [profileTab, setProfileTab] = useState<ProfileTab>("POSTS");
  const [posts, setPosts] = useState<SocialPost[]>([]);
  const [announcements, setAnnouncements] = useState<SocialAnnouncement[]>([]);
  const [statuses, setStatuses] = useState<SocialStatusProfile[]>([]);
  const [ownProfile, setOwnProfile] = useState<PublicProfileView | null>(null);
  const [ownPosts, setOwnPosts] = useState<SocialPost[]>([]);
  const [ownFavorites, setOwnFavorites] = useState<SocialPost[]>([]);
  const [ownCounts, setOwnCounts] = useState({ posts: 0, favorites: 0 });
  const [loading, setLoading] = useState(true);
  const [refreshingStatus, setRefreshingStatus] = useState(false);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchResults, setSearchResults] = useState<PublicProfileView[]>([]);

  const [expandedPostId, setExpandedPostId] = useState<string | null>(null);
  const [comments, setComments] = useState<Record<string, SocialComment[]>>({});
  const [commentsLoading, setCommentsLoading] = useState<string | null>(null);
  const [commentDraft, setCommentDraft] = useState("");
  const [replyTo, setReplyTo] = useState<SocialComment | null>(null);

  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const [notifications, setNotifications] = useState<SocialNotification[]>([]);
  const [unread, setUnread] = useState(0);

  const [announcementOpen, setAnnouncementOpen] = useState<SocialAnnouncement | null>(null);
  const [profileOpen, setProfileOpen] = useState<ProfileBundle | null>(null);
  const [profileLoading, setProfileLoading] = useState(false);
  const [statusMenuOpen, setStatusMenuOpen] = useState(false);
  const [statusViewer, setStatusViewer] = useState<SocialStatusProfile | null>(null);

  const mounted = useRef(true);
  const loadVersion = useRef(0);

  const ownStatusProfile = useMemo(
    () => statuses.find((item) => item.mine) || null,
    [statuses]
  );

  async function loadProfileBundle(profileId: string) {
    const [detail, profilePosts, favorites] = await Promise.all([
      getPublicProfile(sessionToken, deviceToken, profileId),
      getProfilePosts(sessionToken, deviceToken, profileId),
      getProfileFavorites(sessionToken, deviceToken, profileId)
    ]);
    return {
      profile: detail.profile,
      posts: profilePosts.posts,
      favorites: favorites.posts,
      counts: detail.counts
    } satisfies ProfileBundle;
  }

  async function reload(showSpinner = true) {
    const version = ++loadVersion.current;
    if (showSpinner) setLoading(true);
    setMessage(null);
    try {
      const [feed, notices, statusResult, profileResult] = await Promise.all([
        listSocialFeed(sessionToken, deviceToken, 40, 0),
        listSocialNotifications(sessionToken, deviceToken).catch(() => null),
        listSocialStatuses(sessionToken, deviceToken).catch(() => ({ ok: true as const, profiles: [] })),
        getOwnProfile(sessionToken, deviceToken).catch(() => null)
      ]);
      if (!mounted.current || version !== loadVersion.current) return;
      setPosts(feed.posts);
      setAnnouncements(feed.announcements || []);
      setStatuses(statusResult.profiles || []);
      if (profileResult) setOwnProfile(profileResult.profile);
      if (notices) {
        setNotifications(notices.notifications);
        setUnread(Number(notices.unread.ALL || 0));
      }

      if (viewerProfileId) {
        const bundle = await loadProfileBundle(viewerProfileId).catch(() => null);
        if (bundle && mounted.current && version === loadVersion.current) {
          setOwnProfile(bundle.profile);
          setOwnPosts(bundle.posts);
          setOwnFavorites(bundle.favorites);
          setOwnCounts(bundle.counts);
        }
      }
    } catch (error) {
      if (mounted.current && version === loadVersion.current) {
        setMessage(error instanceof Error ? error.message : "Não foi possível carregar o Social.");
      }
    } finally {
      if (mounted.current && version === loadVersion.current && showSpinner) setLoading(false);
    }
  }

  async function refreshStatuses() {
    setRefreshingStatus(true);
    try {
      const result = await listSocialStatuses(sessionToken, deviceToken);
      if (mounted.current) setStatuses(result.profiles);
    } catch (error) {
      if (mounted.current) {
        Alert.alert("Status indisponíveis", error instanceof Error ? error.message : "Não foi possível atualizar os status.");
      }
    } finally {
      if (mounted.current) setRefreshingStatus(false);
    }
  }

  function patchPost(postId: string, updater: (post: SocialPost) => SocialPost) {
    setPosts((current) => current.map((post) => post.id === postId ? updater(post) : post));
    setOwnPosts((current) => current.map((post) => post.id === postId ? updater(post) : post));
    setOwnFavorites((current) => current.map((post) => post.id === postId ? updater(post) : post));
    setProfileOpen((current) => current ? {
      ...current,
      posts: current.posts.map((post) => post.id === postId ? updater(post) : post),
      favorites: current.favorites.map((post) => post.id === postId ? updater(post) : post)
    } : current);
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
      if (viewerProfileId && post.author.profileId === viewerProfileId) {
        const favorites = await getProfileFavorites(sessionToken, deviceToken, viewerProfileId).catch(() => null);
        if (favorites && mounted.current) setOwnFavorites(favorites.posts);
      }
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

  function openPostMenu(post: SocialPost) {
    const buttons: any[] = [
      { text: "Copiar conteúdo", onPress: () => { copyPost(post).catch(() => {}); } }
    ];
    if (viewerRole === "DEV") {
      buttons.push({
        text: post.pinned ? "Desafixar publicação" : "Fixar publicação",
        onPress: () => { togglePin(post).catch(() => {}); }
      });
    }
    buttons.push({ text: "Cancelar", style: "cancel" });
    Alert.alert(post.item.title, "Ações da publicação", buttons);
  }

  async function togglePin(post: SocialPost) {
    if (viewerRole !== "DEV" || busyAction) return;
    setBusyAction(`pin:${post.id}`);
    try {
      await setSocialPostPinned(sessionToken, deviceToken, post.id, !post.pinned);
      if (mounted.current) await reload(false);
    } catch (error) {
      if (mounted.current) Alert.alert("Falha ao fixar", error instanceof Error ? error.message : "A publicação não pôde ser alterada.");
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
    Alert.alert("Apagar comentário?", "O comentário será removido do Social.", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Apagar",
        style: "destructive",
        onPress: () => {
          (async () => {
            try {
              await deleteSocialComment(sessionToken, deviceToken, comment.id);
              if (!mounted.current) return;
              setComments((current) => ({
                ...current,
                [post.id]: (current[post.id] || []).filter((item) => item.id !== comment.id)
              }));
              patchPost(post.id, (current) => ({
                ...current,
                reactions: { ...current.reactions, commentCount: Math.max(0, current.reactions.commentCount - 1) }
              }));
            } catch (error) {
              if (mounted.current) Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível apagar.");
            }
          })().catch(() => {});
        }
      }
    ]);
  }

  async function openNotifications() {
    setNotificationsOpen(true);
    try {
      const result = await listSocialNotifications(sessionToken, deviceToken);
      if (!mounted.current) return;
      setNotifications(result.notifications);
      setUnread(Number(result.unread.ALL || 0));
      if (result.unread.ALL > 0) {
        await markSocialNotificationsRead(sessionToken, deviceToken, {});
        if (mounted.current) setUnread(0);
      }
    } catch (error) {
      if (mounted.current) Alert.alert("Notificações indisponíveis", error instanceof Error ? error.message : "Não foi possível carregar as notificações.");
    }
  }

  async function openPublicProfile(profileId: string | null) {
    if (!profileId) return;
    if (profileId === viewerProfileId) {
      setMainTab("PROFILE");
      setSearch("");
      setSearchResults([]);
      return;
    }
    setProfileLoading(true);
    try {
      const bundle = await loadProfileBundle(profileId);
      if (mounted.current) setProfileOpen(bundle);
    } catch (error) {
      if (mounted.current) Alert.alert("Perfil indisponível", error instanceof Error ? error.message : "Não foi possível abrir o perfil.");
    } finally {
      if (mounted.current) setProfileLoading(false);
    }
  }

  async function pickAndPublishStatus() {
    if (busyAction) return;
    setStatusMenuOpen(false);
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: ["image/jpeg", "image/png", "image/webp"],
        multiple: false,
        copyToCacheDirectory: true
      });
      if (result.canceled || !result.assets?.[0]) return;
      const asset = result.assets[0];
      const mimeType = mimeFromAsset(asset);
      if (!mimeType) {
        Alert.alert("Formato não aceito", "Use uma foto JPG, PNG ou WEBP.");
        return;
      }
      if (typeof asset.size === "number" && asset.size > 4 * 1024 * 1024) {
        Alert.alert("Foto muito grande", "A foto do status pode ter no máximo 4 MB.");
        return;
      }
      setBusyAction("status-upload");
      await uploadSocialStatus(sessionToken, deviceToken, asset.uri, mimeType);
      if (!mounted.current) return;
      await refreshStatuses();
      setMessage("Status publicado por 24 horas.");
    } catch (error) {
      if (mounted.current) Alert.alert("Status não publicado", error instanceof Error ? error.message : "Não foi possível publicar a foto.");
    } finally {
      if (mounted.current) setBusyAction(null);
    }
  }

  function openOwnStatusMenu() {
    setStatusMenuOpen(true);
  }

  function pressStatus(profile: SocialStatusProfile) {
    if (profile.mine) {
      openOwnStatusMenu();
      return;
    }
    if (profile.activeStatus) {
      setStatusViewer(profile);
      return;
    }
    openPublicProfile(profile.profileId).catch(() => {});
  }

  function viewOwnStatus() {
    if (!ownStatusProfile?.activeStatus) return;
    setStatusMenuOpen(false);
    setStatusViewer(ownStatusProfile);
  }

  function deleteOwnStatus() {
    const statusId = ownStatusProfile?.activeStatus?.id;
    if (!statusId) return;
    setStatusMenuOpen(false);
    Alert.alert("Apagar status?", "A foto deixará de aparecer para todos imediatamente.", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Apagar",
        style: "destructive",
        onPress: () => {
          (async () => {
            try {
              setBusyAction("status-delete");
              await deleteSocialStatus(sessionToken, deviceToken, statusId);
              if (!mounted.current) return;
              setStatusViewer(null);
              await refreshStatuses();
            } catch (error) {
              if (mounted.current) Alert.alert("Falha ao apagar", error instanceof Error ? error.message : "Não foi possível apagar o status.");
            } finally {
              if (mounted.current) setBusyAction(null);
            }
          })().catch(() => {});
        }
      }
    ]);
  }

  useEffect(() => {
    mounted.current = true;
    reload(true).catch(() => {});
    return () => {
      mounted.current = false;
      loadVersion.current += 1;
    };
  }, [sessionToken, deviceToken, viewerProfileId]);

  useEffect(() => {
    const q = search.trim();
    if (q.length < 2) {
      setSearchResults([]);
      setSearching(false);
      return;
    }
    let cancelled = false;
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const result = await searchPublicProfiles(sessionToken, deviceToken, q, 15, 0);
        if (!cancelled && mounted.current) setSearchResults(result.profiles);
      } catch {
        if (!cancelled && mounted.current) setSearchResults([]);
      } finally {
        if (!cancelled && mounted.current) setSearching(false);
      }
    }, 350);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [search, sessionToken, deviceToken]);

  const visibleOwnProfile = ownProfile || {
    profileId: viewerProfileId,
    publicName: viewerPublicName,
    role: viewerRole,
    bio: "",
    statusText: "",
    avatarStyle: "MOON",
    frameStyle: "DEFAULT",
    presenceMode: "VISIBLE" as const
  };

  return (
    <View style={s.root}>
      <View style={s.sessionHeader}>
        <Avatar name={viewerPublicName} avatarStyle={visibleOwnProfile.avatarStyle} size={48} highlighted />
        <View style={s.sessionIdentity}>
          <View style={s.nameRow}>
            <Text style={s.sessionName}>{viewerPublicName || "Lua"}</Text>
            <Text style={[s.roleBadge, viewerRole === "DEV" && s.roleBadgeDev]}>{roleText(viewerRole)}</Text>
          </View>
          <Text style={s.sessionMeta}>Sessão até {fullDate(sessionExpiresAt)}</Text>
        </View>
      </View>

      <View style={s.divider} />

      <View style={s.brandRow}>
        <Text style={s.brand}>GRUPO <Text style={s.brandRed}>LUA</Text></Text>
        <View style={s.brandActions}>
          <Pressable
            style={s.headerIconButton}
            onPress={() => openNotifications().catch(() => {})}
            accessibilityRole="button"
            accessibilityLabel="Notificações"
          >
            <SocialIcon name="bell" size={23} />
            {unread > 0 ? <View style={s.unreadDot} /> : null}
          </Pressable>
          <Pressable
            style={s.headerIconButton}
            onPress={onOpenChat}
            accessibilityRole="button"
            accessibilityLabel="Chat"
          >
            <SocialIcon name="chat" size={24} />
          </Pressable>
        </View>
      </View>

      <View style={s.mainTabs}>
        <Pressable style={s.mainTab} onPress={() => setMainTab("FEED")}>
          <Text style={[s.mainTabText, mainTab === "FEED" && s.mainTabTextActive]}>FEED</Text>
          {mainTab === "FEED" ? <View style={s.mainTabLine} /> : null}
        </Pressable>
        <Pressable style={s.mainTab} onPress={() => setMainTab("PROFILE")}>
          <Text style={[s.mainTabText, mainTab === "PROFILE" && s.mainTabTextActive]}>PERFIL</Text>
          {mainTab === "PROFILE" ? <View style={s.mainTabLine} /> : null}
        </Pressable>
      </View>

      {mainTab === "FEED" ? (
        <>
          <ScrollView
            horizontal
            style={s.statusScroller}
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={s.statusStrip}
          >
            {(statuses.length ? statuses : [{
              profileId: viewerProfileId,
              publicName: viewerPublicName,
              role: viewerRole,
              avatarStyle: visibleOwnProfile.avatarStyle,
              frameStyle: visibleOwnProfile.frameStyle,
              statusText: visibleOwnProfile.statusText,
              mine: true,
              activeStatus: null
            }]).map((profile) => {
              const source = profile.activeStatus
                ? socialStatusImageSource(profile.activeStatus.id, sessionToken, deviceToken)
                : null;
              return (
                <Pressable
                  key={`${profile.profileId || profile.publicName}:${profile.mine ? "mine" : "other"}`}
                  style={s.statusItem}
                  onPress={() => pressStatus(profile)}
                >
                  <View style={s.statusAvatarWrap}>
                    <Avatar
                      name={profile.publicName}
                      avatarStyle={profile.avatarStyle}
                      imageSource={source}
                      size={68}
                      highlighted={Boolean(profile.activeStatus) || profile.mine}
                    />
                    {!profile.mine ? (
                      <View style={s.statusRoleBadge}>
                        <Text style={s.statusRoleText}>{roleText(profile.role)}</Text>
                      </View>
                    ) : (
                      <View style={s.addStatusBadge}>
                        <SocialIcon name="plus" size={11} />
                      </View>
                    )}
                  </View>
                  <Text numberOfLines={1} style={s.statusName}>
                    {profile.mine ? "Seu perfil" : profile.publicName}
                  </Text>
                </Pressable>
              );
            })}
            {refreshingStatus ? <ActivityIndicator style={s.statusLoader} /> : null}
          </ScrollView>

          <View style={s.searchBox}>
            <SocialIcon name="search" size={19} color="rgba(245,245,248,0.88)" />
            <TextInput
              value={search}
              onChangeText={setSearch}
              style={s.searchInput}
              placeholder="Buscar perfis"
              placeholderTextColor="rgba(230,230,236,0.55)"
              autoCapitalize="none"
              autoCorrect={false}
            />
            {searching ? <ActivityIndicator size="small" /> : null}
          </View>

          {searchResults.length > 0 ? (
            <View style={s.searchResults}>
              {searchResults.map((profile) => (
                <Pressable
                  key={profile.profileId || profile.publicName}
                  style={s.searchResult}
                  onPress={() => openPublicProfile(profile.profileId).catch(() => {})}
                >
                  <Avatar name={profile.publicName} avatarStyle={profile.avatarStyle} size={38} />
                  <View style={{ flex: 1 }}>
                    <View style={s.nameRow}>
                      <Text style={s.searchName}>{profile.publicName}</Text>
                      <Text style={s.miniRole}>{roleText(profile.role)}</Text>
                    </View>
                    <Text numberOfLines={1} style={s.searchMeta}>{profile.statusText || profile.bio || "Abrir perfil"}</Text>
                  </View>
                  <SocialIcon name="chevron" size={18} color="rgba(255,255,255,0.55)" />
                </Pressable>
              ))}
            </View>
          ) : null}

          {announcements[0] ? (
            <Pressable style={s.devNotice} onPress={() => setAnnouncementOpen(announcements[0])}>
              <View style={s.devNoticeIconBox}>
                <SocialIcon name="notice" size={18} color="#FF2638" />
              </View>
              <View style={s.devNoticeBody}>
                <Text numberOfLines={1} style={s.devNoticeText}>
                  <Text style={s.devNoticeLabel}>AVISO DEV</Text>
                  <Text style={s.devNoticeDot}>  •  </Text>
                  {announcements[0].text}
                </Text>
              </View>
              <Text style={s.devNoticeDate}>{shortDate(announcements[0].createdAt)}</Text>
            </Pressable>
          ) : null}

          {message ? (
            <Pressable style={s.messageBar} onPress={() => reload(true).catch(() => {})}>
              <Text style={s.messageText}>{message}</Text>
            </Pressable>
          ) : null}

          {loading ? <ActivityIndicator style={s.feedLoader} /> : null}
          {!loading && posts.length === 0 ? (
            <View style={s.emptyFeed}>
              <Text style={s.emptyFeedTitle}>Feed vazio</Text>
              <Text style={s.emptyFeedText}>As publicações compartilhadas em Arquivos aparecerão aqui.</Text>
            </View>
          ) : null}

          {!loading ? posts.map((post) => (
            <PostBlock
              key={post.id}
              post={post}
              comments={comments[post.id] || []}
              expanded={expandedPostId === post.id}
              commentsLoading={commentsLoading === post.id}
              commentDraft={expandedPostId === post.id ? commentDraft : ""}
              replyTo={expandedPostId === post.id ? replyTo : null}
              busy={Boolean(busyAction)}
              onAuthor={() => openPublicProfile(post.author.profileId).catch(() => {})}
              onLike={() => toggleLike(post).catch(() => {})}
              onComments={() => openComments(post).catch(() => {})}
              onFavorite={() => toggleFavorite(post).catch(() => {})}
              onMenu={() => openPostMenu(post)}
              onDraft={setCommentDraft}
              onSubmit={() => submitComment(post).catch(() => {})}
              onReply={(comment) => {
                setReplyTo(comment);
                setCommentDraft(`@${comment.author.publicName} `);
              }}
              onDeleteComment={(comment) => confirmDeleteComment(post, comment)}
            />
          )) : null}
        </>
      ) : (
        <OwnProfilePanel
          profile={visibleOwnProfile}
          role={viewerRole}
          counts={ownCounts}
          profileTab={profileTab}
          onProfileTab={setProfileTab}
          posts={profileTab === "POSTS" ? ownPosts : ownFavorites}
          onEdit={onOpenProfile}
          onPost={(post) => {
            setMainTab("FEED");
            setExpandedPostId(post.id);
          }}
        />
      )}

      <Modal visible={statusMenuOpen} transparent animationType="fade" onRequestClose={() => setStatusMenuOpen(false)}>
        <Pressable style={s.modalBackdropBottom} onPress={() => setStatusMenuOpen(false)}>
          <Pressable style={s.actionSheet} onPress={(event) => event.stopPropagation()}>
            <View style={s.actionSheetHandle} />
            <Text style={s.actionSheetTitle}>Seu status</Text>
            <Pressable style={s.actionRow} onPress={() => pickAndPublishStatus().catch(() => {})}>
              <View style={s.actionIconBox}><SocialIcon name="plus" size={21} /></View>
              <View style={{ flex: 1 }}>
                <Text style={s.actionTitle}>Postar foto</Text>
                <Text style={s.actionMeta}>JPG, PNG ou WEBP • até 4 MB • 24 horas</Text>
              </View>
            </Pressable>
            {ownStatusProfile?.activeStatus ? (
              <Pressable style={s.actionRow} onPress={viewOwnStatus}>
                <View style={s.actionIconBox}><SocialIcon name="eye" size={21} /></View>
                <Text style={s.actionTitle}>Ver status</Text>
              </Pressable>
            ) : null}
            <Pressable
              style={s.actionRow}
              onPress={() => {
                setStatusMenuOpen(false);
                setMainTab("PROFILE");
              }}
            >
              <View style={s.actionIconBox}><SocialIcon name="profile" size={21} /></View>
              <Text style={s.actionTitle}>Entrar no perfil</Text>
            </Pressable>
            {ownStatusProfile?.activeStatus ? (
              <Pressable style={s.actionRow} onPress={deleteOwnStatus}>
                <View style={s.actionIconBox}><SocialIcon name="trash" size={21} color="#FF6672" /></View>
                <Text style={[s.actionTitle, s.dangerText]}>Apagar status</Text>
              </Pressable>
            ) : null}
          </Pressable>
        </Pressable>
      </Modal>

      <Modal visible={Boolean(statusViewer)} transparent animationType="fade" onRequestClose={() => setStatusViewer(null)}>
        <View style={s.statusViewerBackdrop}>
          {statusViewer?.activeStatus ? (
            <>
              <View style={s.statusViewerHeader}>
                <Pressable onPress={() => openPublicProfile(statusViewer.profileId).catch(() => {})} style={s.statusViewerIdentity}>
                  <Avatar name={statusViewer.publicName} avatarStyle={statusViewer.avatarStyle} size={38} highlighted />
                  <View style={{ flex: 1 }}>
                    <View style={s.nameRow}>
                      <Text style={s.statusViewerName}>{statusViewer.publicName}</Text>
                      <Text style={s.miniRole}>{roleText(statusViewer.role)}</Text>
                    </View>
                    <Text style={s.statusViewerTime}>{relativeDate(statusViewer.activeStatus.createdAt)}</Text>
                  </View>
                </Pressable>
                <Pressable style={s.closeCircle} onPress={() => setStatusViewer(null)} accessibilityLabel="Fechar status">
                  <SocialIcon name="close" size={19} />
                </Pressable>
              </View>
              <Image
                source={socialStatusImageSource(statusViewer.activeStatus.id, sessionToken, deviceToken)}
                style={s.statusViewerImage}
                resizeMode="contain"
              />
              <View style={s.statusViewerFooter}>
                <Pressable
                  style={s.viewerProfileButton}
                  onPress={() => {
                    const profileId = statusViewer.profileId;
                    setStatusViewer(null);
                    openPublicProfile(profileId).catch(() => {});
                  }}
                >
                  <Text style={s.viewerProfileButtonText}>VER PERFIL</Text>
                </Pressable>
                {statusViewer.mine ? (
                  <Pressable style={s.viewerDeleteButton} onPress={deleteOwnStatus}>
                    <Text style={s.viewerDeleteButtonText}>APAGAR</Text>
                  </Pressable>
                ) : null}
              </View>
            </>
          ) : null}
        </View>
      </Modal>

      <Modal visible={notificationsOpen} transparent animationType="fade" onRequestClose={() => setNotificationsOpen(false)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalPanel}>
            <View style={s.modalHeader}>
              <Text style={s.modalTitle}>Notificações</Text>
              <Pressable style={s.modalCloseButton} onPress={() => setNotificationsOpen(false)} accessibilityLabel="Fechar notificações"><SocialIcon name="close" size={18} /></Pressable>
            </View>
            <ScrollView style={s.modalList} contentContainerStyle={s.modalListContent}>
              {notifications.length === 0 ? (
                <Text style={s.modalEmpty}>Nenhuma notificação.</Text>
              ) : notifications.map((notice) => (
                <Pressable
                  key={notice.id}
                  style={s.notificationRow}
                  onPress={() => {
                    if (notice.postId) {
                      setNotificationsOpen(false);
                      setMainTab("FEED");
                      setExpandedPostId(notice.kind === "COMMENT" ? notice.postId : null);
                    }
                  }}
                >
                  <Text style={s.notificationText}>{notificationText(notice)}</Text>
                  <Text style={s.notificationDate}>{fullDate(notice.createdAt)}</Text>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal visible={Boolean(announcementOpen)} transparent animationType="fade" onRequestClose={() => setAnnouncementOpen(null)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalPanelCompact}>
            <View style={s.modalHeader}>
              <Text style={s.devNoticeLabel}>AVISO DEV</Text>
              <Pressable style={s.modalCloseButton} onPress={() => setAnnouncementOpen(null)} accessibilityLabel="Fechar aviso"><SocialIcon name="close" size={18} /></Pressable>
            </View>
            <Text style={s.announcementText}>{announcementOpen?.text}</Text>
            <Text style={s.announcementMeta}>
              {announcementOpen?.author.publicName} • {fullDate(announcementOpen?.createdAt)}
            </Text>
          </View>
        </View>
      </Modal>

      <Modal visible={profileLoading || Boolean(profileOpen)} transparent animationType="fade" onRequestClose={() => setProfileOpen(null)}>
        <View style={s.modalBackdrop}>
          <View style={s.modalPanel}>
            {profileLoading && !profileOpen ? (
              <ActivityIndicator style={{ marginVertical: 40 }} />
            ) : profileOpen ? (
              <PublicProfilePanel
                bundle={profileOpen}
                onClose={() => setProfileOpen(null)}
              />
            ) : null}
          </View>
        </View>
      </Modal>
    </View>
  );
}

function PostBlock({
  post,
  comments,
  expanded,
  commentsLoading,
  commentDraft,
  replyTo,
  busy,
  onAuthor,
  onLike,
  onComments,
  onFavorite,
  onMenu,
  onDraft,
  onSubmit,
  onReply,
  onDeleteComment
}: {
  post: SocialPost;
  comments: SocialComment[];
  expanded: boolean;
  commentsLoading: boolean;
  commentDraft: string;
  replyTo: SocialComment | null;
  busy: boolean;
  onAuthor: () => void;
  onLike: () => void;
  onComments: () => void;
  onFavorite: () => void;
  onMenu: () => void;
  onDraft: (value: string) => void;
  onSubmit: () => void;
  onReply: (comment: SocialComment) => void;
  onDeleteComment: (comment: SocialComment) => void;
}) {
  return (
    <View style={[s.post, post.pinned && s.postPinned]}>
      {post.pinned ? <Text style={s.pinnedLabel}>FIXADO PELO GRUPO LUA</Text> : null}
      <View style={s.postHeader}>
        <Pressable onPress={onAuthor}>
          <Avatar name={post.author.publicName} avatarStyle={post.author.avatarStyle} size={46} highlighted={post.author.role === "DEV"} />
        </Pressable>
        <Pressable style={s.postIdentity} onPress={onAuthor}>
          <View style={s.nameRow}>
            <Text style={s.postAuthor}>{post.author.publicName}</Text>
            <Text style={[s.postRole, post.author.role === "DEV" && s.postRoleDev]}>{roleText(post.author.role)}</Text>
          </View>
          <Text style={s.postTime}>{relativeDate(post.createdAt)}</Text>
        </Pressable>
        <Pressable style={s.moreButton} onPress={onMenu} accessibilityLabel="Mais ações">
          <SocialIcon name="more" size={22} />
        </Pressable>
      </View>

      <View style={s.postMedia}>
        <Text style={s.postBrand}>GRUPO <Text style={s.brandRed}>LUA</Text></Text>
        <Text style={s.postHeroTitle}>{post.item.title}</Text>
        <Text style={s.postHeroSubtitle}>{post.kind === "CODE" ? "Código disponível" : "Loadstring disponível"}</Text>
        <View style={s.codePanel}>
          <Text numberOfLines={9} style={s.codeText}>{post.item.content}</Text>
        </View>
      </View>

      <View style={s.postActions}>
        <Pressable disabled={busy} onPress={onLike} style={s.postAction} accessibilityLabel={post.reactions.liked ? "Descurtir" : "Curtir"}>
          <SocialIcon name="heart" size={24} active={post.reactions.liked} />
        </Pressable>
        <Pressable onPress={onComments} style={s.postAction} accessibilityLabel="Comentários">
          <SocialIcon name="chat" size={23} />
        </Pressable>
        <Pressable disabled={busy} onPress={onFavorite} style={s.postAction} accessibilityLabel={post.reactions.favorited ? "Remover dos favoritos" : "Favoritar"}>
          <SocialIcon name="favorite" size={23} active={post.reactions.favorited} />
        </Pressable>
      </View>

      <Text style={s.likesText}>{post.reactions.likeCount} curtida{post.reactions.likeCount === 1 ? "" : "s"}</Text>
      {post.comment ? (
        <Text style={s.caption}><Text style={s.captionAuthor}>{post.author.publicName}</Text>  {post.comment}</Text>
      ) : null}
      <Pressable onPress={onComments}>
        <Text style={s.viewComments}>Ver {post.reactions.commentCount} comentário{post.reactions.commentCount === 1 ? "" : "s"}</Text>
      </Pressable>

      {expanded ? (
        <View style={s.commentsArea}>
          {commentsLoading ? <ActivityIndicator style={{ marginVertical: 12 }} /> : null}
          {!commentsLoading && comments.length === 0 ? <Text style={s.noComments}>Nenhum comentário ainda.</Text> : null}
          {comments.map((comment) => (
            <View key={comment.id} style={[s.commentRow, comment.parentCommentId && s.commentReply]}>
              <View style={s.commentHeader}>
                <Text style={s.commentAuthor}>{comment.author.publicName}</Text>
                <Text style={s.commentTime}>{relativeDate(comment.createdAt)}</Text>
              </View>
              <Text style={s.commentText}>{comment.text}</Text>
              <View style={s.commentButtons}>
                <Pressable onPress={() => onReply(comment)}><Text style={s.commentButton}>RESPONDER</Text></Pressable>
                {comment.mine ? <Pressable onPress={() => onDeleteComment(comment)}><Text style={s.commentDelete}>APAGAR</Text></Pressable> : null}
              </View>
            </View>
          ))}
          {replyTo ? <Text style={s.replyingTo}>Respondendo a {replyTo.author.publicName}</Text> : null}
          <View style={s.commentComposer}>
            <TextInput
              value={commentDraft}
              onChangeText={onDraft}
              style={s.commentInput}
              multiline
              maxLength={1000}
              placeholder="Adicionar comentário..."
              placeholderTextColor="rgba(230,230,236,0.45)"
            />
            <Pressable disabled={!commentDraft.trim() || busy} onPress={onSubmit} style={[s.commentSend, (!commentDraft.trim() || busy) && s.disabled]}>
              <Text style={s.commentSendText}>ENVIAR</Text>
            </Pressable>
          </View>
        </View>
      ) : null}
    </View>
  );
}

function OwnProfilePanel({
  profile,
  role,
  counts,
  profileTab,
  onProfileTab,
  posts,
  onEdit,
  onPost
}: {
  profile: PublicProfileView;
  role: App1Role;
  counts: { posts: number; favorites: number };
  profileTab: ProfileTab;
  onProfileTab: (tab: ProfileTab) => void;
  posts: SocialPost[];
  onEdit: () => void;
  onPost: (post: SocialPost) => void;
}) {
  return (
    <View style={s.profilePage}>
      <View style={s.profileHero}>
        <Avatar name={profile.publicName} avatarStyle={profile.avatarStyle} size={86} highlighted />
        <View style={s.profileHeroBody}>
          <View style={s.nameRow}>
            <Text style={s.profileName}>{profile.publicName}</Text>
            <Text style={[s.roleBadge, role === "DEV" && s.roleBadgeDev]}>{roleText(role)}</Text>
          </View>
          <Text style={s.profileStatus}>{profile.statusText || "Perfil GRUPO LUA"}</Text>
        </View>
      </View>
      {profile.bio ? <Text style={s.profileBio}>{profile.bio}</Text> : null}
      <View style={s.profileCounters}>
        <Text style={s.profileCounter}><Text style={s.profileCounterStrong}>{counts.posts}</Text>{"\n"}posts</Text>
        <Text style={s.profileCounter}><Text style={s.profileCounterStrong}>{counts.favorites}</Text>{"\n"}favoritos</Text>
      </View>
      <Pressable style={s.editProfileButton} onPress={onEdit}><Text style={s.editProfileText}>EDITAR PERFIL E CONFIGURAÇÕES</Text></Pressable>
      <View style={s.profileTabs}>
        <Pressable style={[s.profileTabButton, profileTab === "POSTS" && s.profileTabButtonActive]} onPress={() => onProfileTab("POSTS")}>
          <Text style={s.profileTabText}>PUBLICAÇÕES</Text>
        </Pressable>
        <Pressable style={[s.profileTabButton, profileTab === "FAVORITES" && s.profileTabButtonActive]} onPress={() => onProfileTab("FAVORITES")}>
          <Text style={s.profileTabText}>FAVORITOS</Text>
        </Pressable>
      </View>
      {posts.length === 0 ? <Text style={s.modalEmpty}>Nada aqui ainda.</Text> : posts.map((post) => (
        <Pressable key={post.id} style={s.profilePost} onPress={() => onPost(post)}>
          <Text style={s.profilePostTitle}>{post.item.title}</Text>
          <Text numberOfLines={2} style={s.profilePostCode}>{post.item.content}</Text>
          <Text style={s.profilePostMeta}>{shortDate(post.createdAt)} • {post.reactions.likeCount} curtidas</Text>
        </Pressable>
      ))}
    </View>
  );
}

function PublicProfilePanel({ bundle, onClose }: { bundle: ProfileBundle; onClose: () => void }) {
  const [tab, setTab] = useState<ProfileTab>("POSTS");
  const items = tab === "POSTS" ? bundle.posts : bundle.favorites;
  return (
    <>
      <View style={s.modalHeader}>
        <Text style={s.modalTitle}>Perfil</Text>
        <Pressable style={s.modalCloseButton} onPress={onClose} accessibilityLabel="Fechar perfil"><SocialIcon name="close" size={18} /></Pressable>
      </View>
      <View style={s.publicProfileHero}>
        <Avatar name={bundle.profile.publicName} avatarStyle={bundle.profile.avatarStyle} size={72} highlighted={bundle.profile.role === "DEV"} />
        <View style={{ flex: 1 }}>
          <View style={s.nameRow}>
            <Text style={s.profileName}>{bundle.profile.publicName}</Text>
            <Text style={s.miniRole}>{roleText(bundle.profile.role)}</Text>
          </View>
          <Text style={s.profileStatus}>{bundle.profile.statusText || "Perfil GRUPO LUA"}</Text>
        </View>
      </View>
      {bundle.profile.bio ? <Text style={s.profileBio}>{bundle.profile.bio}</Text> : null}
      <Text style={s.publicProfileCounts}>{bundle.counts.posts} posts • {bundle.counts.favorites} favoritos</Text>
      <View style={s.profileTabs}>
        <Pressable style={[s.profileTabButton, tab === "POSTS" && s.profileTabButtonActive]} onPress={() => setTab("POSTS")}>
          <Text style={s.profileTabText}>PUBLICAÇÕES</Text>
        </Pressable>
        <Pressable style={[s.profileTabButton, tab === "FAVORITES" && s.profileTabButtonActive]} onPress={() => setTab("FAVORITES")}>
          <Text style={s.profileTabText}>FAVORITOS</Text>
        </Pressable>
      </View>
      <ScrollView style={s.modalList} contentContainerStyle={s.modalListContent}>
        {items.length === 0 ? <Text style={s.modalEmpty}>Nada aqui ainda.</Text> : items.map((post) => (
          <View key={post.id} style={s.profilePost}>
            <Text style={s.profilePostTitle}>{post.item.title}</Text>
            <Text numberOfLines={3} style={s.profilePostCode}>{post.item.content}</Text>
          </View>
        ))}
      </ScrollView>
    </>
  );
}

const s = StyleSheet.create({
  root: { width: "100%" },
  iconBox: { alignItems: "center", justifyContent: "center", position: "relative", flexShrink: 0 },
  sessionHeader: { flexDirection: "row", alignItems: "center", gap: 10, marginHorizontal: -12, paddingHorizontal: 14, paddingTop: 4, paddingBottom: 10 },
  sessionIdentity: { flex: 1 },
  sessionName: { color: "#FFFFFF", fontSize: 15, fontWeight: "900" },
  sessionMeta: { color: "rgba(240,240,244,0.70)", fontSize: 9, marginTop: 3 },
  nameRow: { flexDirection: "row", alignItems: "center", gap: 7, flexWrap: "wrap" },
  roleBadge: { color: "#FFFFFF", backgroundColor: "rgba(111,24,30,0.78)", borderRadius: 6, paddingHorizontal: 7, paddingVertical: 3, fontSize: 8, fontWeight: "900" },
  roleBadgeDev: { backgroundColor: "rgba(123,17,24,0.88)" },
  divider: { height: 1, backgroundColor: "rgba(255,255,255,0.16)", marginHorizontal: -12 },
  brandRow: { minHeight: 52, flexDirection: "row", alignItems: "center", marginHorizontal: -12, paddingHorizontal: 14 },
  brand: { flex: 1, color: "#E7E7EC", fontSize: 16, fontWeight: "900", letterSpacing: 3.6 },
  brandRed: { color: "#FF3344" },
  brandActions: { flexDirection: "row", gap: 4 },
  headerIconButton: { width: 38, height: 38, alignItems: "center", justifyContent: "center", position: "relative" },
  headerIcon: { color: "#FFFFFF", fontSize: 26, transform: [{ rotate: "45deg" }] },
  chatBubble: { color: "#FFFFFF", fontSize: 30, lineHeight: 32 },
  unreadDot: { position: "absolute", width: 8, height: 8, borderRadius: 4, backgroundColor: "#FF2638", right: 5, top: 5 },
  mainTabs: { flexDirection: "row", borderBottomWidth: 1, borderBottomColor: "rgba(255,255,255,0.14)", marginHorizontal: -12 },
  mainTab: { flex: 1, minHeight: 44, alignItems: "center", justifyContent: "center", position: "relative" },
  mainTabText: { color: "rgba(220,220,230,0.56)", fontSize: 12, fontWeight: "900", letterSpacing: 0.3 },
  mainTabTextActive: { color: "#FFFFFF" },
  mainTabLine: { position: "absolute", left: 32, right: 32, bottom: -1, height: 3, backgroundColor: "#FF2638" },
  statusScroller: { marginHorizontal: -12 },
  statusStrip: { paddingHorizontal: 14, paddingTop: 14, paddingBottom: 12, gap: 10 },
  statusItem: { width: 76, alignItems: "center" },
  statusAvatarWrap: { position: "relative" },
  statusName: { color: "#F5F5F7", fontSize: 9, marginTop: 6, maxWidth: 76, textAlign: "center" },
  statusRoleBadge: { position: "absolute", bottom: -4, alignSelf: "center", left: 15, right: 15, borderRadius: 7, borderWidth: 1, borderColor: "#FF3344", backgroundColor: "rgba(20,6,8,0.90)", alignItems: "center", paddingVertical: 1 },
  statusRoleText: { color: "#FFFFFF", fontSize: 7, fontWeight: "900" },
  addStatusBadge: { position: "absolute", right: 0, bottom: 0, width: 19, height: 19, borderRadius: 10, backgroundColor: "#FF2638", borderWidth: 2, borderColor: "#09090B", alignItems: "center", justifyContent: "center" },
  addStatusText: { color: "#FFFFFF", fontSize: 15, fontWeight: "900", marginTop: -2 },
  statusLoader: { alignSelf: "center", marginHorizontal: 12 },
  avatar: { borderWidth: 1.3, borderColor: "rgba(255,255,255,0.42)", backgroundColor: "rgba(0,0,0,0.38)", alignItems: "center", justifyContent: "center", overflow: "hidden" },
  avatarHighlighted: { borderWidth: 2.2, borderColor: "#FF2638" },
  avatarGlyph: { color: "#FFFFFF", fontSize: 20, fontWeight: "900" },
  avatarCode: { fontSize: 11 },
  searchBox: { minHeight: 46, borderRadius: 12, borderWidth: 1, borderColor: "rgba(255,255,255,0.22)", backgroundColor: "rgba(7,7,9,0.28)", flexDirection: "row", alignItems: "center", paddingHorizontal: 13, marginHorizontal: 2, gap: 9 },
  searchIcon: { color: "#FFFFFF", fontSize: 27, lineHeight: 29 },
  searchInput: { flex: 1, minHeight: 44, color: "#FFFFFF", fontSize: 12 },
  searchResults: { marginTop: 6, borderRadius: 13, borderWidth: 1, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(5,5,7,0.82)", overflow: "hidden" },
  searchResult: { flexDirection: "row", alignItems: "center", gap: 10, padding: 10, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "rgba(255,255,255,0.12)" },
  searchName: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  searchMeta: { color: "rgba(225,225,232,0.58)", fontSize: 8, marginTop: 3 },
  miniRole: { color: "#FF8A92", fontSize: 7, fontWeight: "900" },
  chevron: { color: "rgba(255,255,255,0.55)", fontSize: 22 },
  devNotice: { minHeight: 50, borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,38,56,0.74)", backgroundColor: "rgba(35,2,7,0.24)", flexDirection: "row", alignItems: "center", marginTop: 11, paddingHorizontal: 12, gap: 9 },
  devNoticeIcon: { color: "#FF2638", fontSize: 22 },
  devNoticeIconBox: { width: 24, alignItems: "center", justifyContent: "center" },
  devNoticeBody: { flex: 1 },
  devNoticeText: { color: "#FFFFFF", fontSize: 11 },
  devNoticeLabel: { color: "#FF4050", fontSize: 10, fontWeight: "900", letterSpacing: 0.4 },
  devNoticeDot: { color: "#FFFFFF" },
  devNoticeDate: { color: "rgba(245,245,248,0.78)", fontSize: 9 },
  messageBar: { marginTop: 9, borderRadius: 10, backgroundColor: "rgba(0,0,0,0.28)", padding: 9 },
  messageText: { color: "rgba(245,245,248,0.78)", fontSize: 9 },
  feedLoader: { marginVertical: 30 },
  emptyFeed: { paddingVertical: 36, alignItems: "center" },
  emptyFeedTitle: { color: "#FFFFFF", fontSize: 16, fontWeight: "900" },
  emptyFeedText: { color: "rgba(235,235,240,0.62)", fontSize: 10, marginTop: 6, textAlign: "center" },
  post: { marginHorizontal: -12, marginTop: 10, borderTopWidth: 1, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: "rgba(255,255,255,0.14)", backgroundColor: "rgba(3,3,5,0.08)", paddingHorizontal: 14, paddingTop: 12, paddingBottom: 14 },
  postPinned: { borderTopColor: "rgba(255,38,56,0.68)" },
  pinnedLabel: { color: "#FF6570", fontSize: 7, fontWeight: "900", letterSpacing: 0.8, marginBottom: 8 },
  postHeader: { flexDirection: "row", alignItems: "center", gap: 10 },
  postIdentity: { flex: 1 },
  postAuthor: { color: "#FFFFFF", fontSize: 13, fontWeight: "900" },
  postRole: { color: "#FFFFFF", backgroundColor: "rgba(91,32,38,0.72)", borderRadius: 5, paddingHorizontal: 6, paddingVertical: 2, fontSize: 7, fontWeight: "900" },
  postRoleDev: { backgroundColor: "rgba(121,17,24,0.84)" },
  postTime: { color: "rgba(225,225,232,0.57)", fontSize: 8, marginTop: 3 },
  moreButton: { width: 34, height: 40, alignItems: "center", justifyContent: "center" },
  moreText: { color: "#FFFFFF", fontSize: 27, lineHeight: 28 },
  postMedia: { borderRadius: 4, borderWidth: 0, backgroundColor: "rgba(5,5,7,0.22)", paddingHorizontal: 14, paddingVertical: 16, marginTop: 10, minHeight: 220 },
  postBrand: { color: "rgba(220,220,228,0.82)", fontSize: 9, fontWeight: "900", letterSpacing: 3.4 },
  postHeroTitle: { color: "#FFFFFF", fontSize: 21, lineHeight: 25, fontWeight: "900", marginTop: 11 },
  postHeroSubtitle: { color: "rgba(210,210,222,0.68)", fontSize: 11, marginTop: 2 },
  codePanel: { borderRadius: 6, borderWidth: StyleSheet.hairlineWidth, borderColor: "rgba(255,255,255,0.10)", backgroundColor: "rgba(0,0,0,0.24)", marginTop: 12, padding: 11 },
  codeText: { color: "#E3E3E8", fontFamily: "monospace", fontSize: 9, lineHeight: 14 },
  postActions: { flexDirection: "row", alignItems: "center", gap: 12, marginTop: 10 },
  postAction: { width: 31, minHeight: 32, alignItems: "center", justifyContent: "center" },
  likeIcon: { color: "#FFFFFF", fontSize: 31, lineHeight: 32 },
  likeIconActive: { color: "#FF2638" },
  commentIcon: { color: "#FFFFFF", fontSize: 31, lineHeight: 32 },
  starIcon: { color: "#FFFFFF", fontSize: 32, lineHeight: 32 },
  starIconActive: { color: "#FFFFFF" },
  likesText: { color: "#FFFFFF", fontSize: 11, fontWeight: "900", marginTop: 4 },
  caption: { color: "#EEEEF2", fontSize: 11, lineHeight: 17, marginTop: 7 },
  captionAuthor: { color: "#FFFFFF", fontWeight: "900" },
  viewComments: { color: "rgba(220,220,230,0.58)", fontSize: 10, marginTop: 7 },
  commentsArea: { marginTop: 11, borderTopWidth: 1, borderTopColor: "rgba(255,255,255,0.12)", paddingTop: 8 },
  noComments: { color: "rgba(225,225,232,0.58)", fontSize: 10, textAlign: "center", marginVertical: 11 },
  commentRow: { backgroundColor: "rgba(0,0,0,0.22)", borderRadius: 10, padding: 9, marginTop: 6 },
  commentReply: { marginLeft: 20, borderLeftWidth: 2, borderLeftColor: "rgba(255,38,56,0.52)" },
  commentHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  commentAuthor: { color: "#FFFFFF", fontSize: 9, fontWeight: "900" },
  commentTime: { color: "rgba(225,225,232,0.52)", fontSize: 7 },
  commentText: { color: "#ECECF0", fontSize: 10, lineHeight: 15, marginTop: 4 },
  commentButtons: { flexDirection: "row", gap: 13, marginTop: 6 },
  commentButton: { color: "rgba(245,245,248,0.70)", fontSize: 7, fontWeight: "900" },
  commentDelete: { color: "#FF6B76", fontSize: 7, fontWeight: "900" },
  replyingTo: { color: "#FF9BA2", fontSize: 8, marginTop: 8 },
  commentComposer: { flexDirection: "row", alignItems: "flex-end", gap: 7, marginTop: 8 },
  commentInput: { flex: 1, minHeight: 44, maxHeight: 110, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.15)", backgroundColor: "rgba(0,0,0,0.24)", color: "#FFFFFF", paddingHorizontal: 10, paddingVertical: 8 },
  commentSend: { minHeight: 44, borderRadius: 10, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center", paddingHorizontal: 10 },
  commentSendText: { color: "#050505", fontSize: 7, fontWeight: "900" },
  disabled: { opacity: 0.4 },
  profilePage: { paddingTop: 18, paddingHorizontal: 4 },
  profileHero: { flexDirection: "row", alignItems: "center", gap: 14 },
  profileHeroBody: { flex: 1 },
  profileName: { color: "#FFFFFF", fontSize: 20, fontWeight: "900" },
  profileStatus: { color: "rgba(235,235,240,0.68)", fontSize: 10, marginTop: 5 },
  profileBio: { color: "#EEEEF2", fontSize: 11, lineHeight: 17, marginTop: 13 },
  profileCounters: { flexDirection: "row", gap: 28, marginTop: 15 },
  profileCounter: { color: "rgba(230,230,236,0.65)", fontSize: 9, textAlign: "center" },
  profileCounterStrong: { color: "#FFFFFF", fontSize: 15, fontWeight: "900" },
  editProfileButton: { minHeight: 42, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.20)", backgroundColor: "rgba(0,0,0,0.25)", alignItems: "center", justifyContent: "center", marginTop: 16 },
  editProfileText: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  profileTabs: { flexDirection: "row", marginTop: 15, gap: 7 },
  profileTabButton: { flex: 1, minHeight: 38, borderRadius: 9, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", alignItems: "center", justifyContent: "center", backgroundColor: "rgba(0,0,0,0.18)" },
  profileTabButtonActive: { borderColor: "rgba(255,38,56,0.70)", backgroundColor: "rgba(81,8,14,0.28)" },
  profileTabText: { color: "#FFFFFF", fontSize: 7, fontWeight: "900" },
  profilePost: { borderRadius: 11, borderWidth: 1, borderColor: "rgba(255,255,255,0.13)", backgroundColor: "rgba(0,0,0,0.24)", padding: 11, marginTop: 8 },
  profilePostTitle: { color: "#FFFFFF", fontSize: 11, fontWeight: "900" },
  profilePostCode: { color: "rgba(230,230,236,0.67)", fontFamily: "monospace", fontSize: 8, lineHeight: 12, marginTop: 5 },
  profilePostMeta: { color: "rgba(225,225,232,0.46)", fontSize: 7, marginTop: 7 },
  modalBackdropBottom: { flex: 1, backgroundColor: "rgba(0,0,0,0.66)", justifyContent: "flex-end" },
  actionSheet: { borderTopLeftRadius: 22, borderTopRightRadius: 22, borderWidth: 1, borderBottomWidth: 0, borderColor: "rgba(255,255,255,0.18)", backgroundColor: "rgba(8,8,10,0.97)", padding: 16, paddingBottom: 28 },
  actionSheetHandle: { width: 44, height: 4, borderRadius: 2, backgroundColor: "rgba(255,255,255,0.30)", alignSelf: "center", marginBottom: 12 },
  actionSheetTitle: { color: "#FFFFFF", fontSize: 17, fontWeight: "900", marginBottom: 8 },
  actionRow: { minHeight: 58, flexDirection: "row", alignItems: "center", gap: 13, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "rgba(255,255,255,0.11)" },
  actionIcon: { color: "#FFFFFF", fontSize: 23, width: 30, textAlign: "center" },
  actionIconBox: { width: 30, alignItems: "center", justifyContent: "center" },
  actionTitle: { color: "#FFFFFF", fontSize: 12, fontWeight: "800" },
  actionMeta: { color: "rgba(225,225,232,0.50)", fontSize: 8, marginTop: 3 },
  dangerText: { color: "#FF6672" },
  statusViewerBackdrop: { flex: 1, backgroundColor: "#050506", paddingTop: 20, paddingBottom: 18 },
  statusViewerHeader: { minHeight: 58, flexDirection: "row", alignItems: "center", paddingHorizontal: 14, gap: 10 },
  statusViewerIdentity: { flex: 1, flexDirection: "row", alignItems: "center", gap: 9 },
  statusViewerName: { color: "#FFFFFF", fontSize: 12, fontWeight: "900" },
  statusViewerTime: { color: "rgba(235,235,240,0.55)", fontSize: 8, marginTop: 2 },
  closeCircle: { width: 38, height: 38, borderRadius: 19, backgroundColor: "rgba(255,255,255,0.08)", alignItems: "center", justifyContent: "center" },
  closeText: { color: "#FFFFFF", fontSize: 24 },
  statusViewerImage: { flex: 1, width: "100%" },
  statusViewerFooter: { flexDirection: "row", gap: 9, paddingHorizontal: 14, paddingTop: 12 },
  viewerProfileButton: { flex: 1, minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.22)", alignItems: "center", justifyContent: "center" },
  viewerProfileButtonText: { color: "#FFFFFF", fontSize: 8, fontWeight: "900" },
  viewerDeleteButton: { minWidth: 88, minHeight: 44, borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,54,69,0.48)", alignItems: "center", justifyContent: "center" },
  viewerDeleteButtonText: { color: "#FF6B76", fontSize: 8, fontWeight: "900" },
  modalBackdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.72)", alignItems: "center", justifyContent: "center", padding: 16 },
  modalPanel: { width: "100%", maxWidth: 540, maxHeight: "86%", borderRadius: 19, borderWidth: 1, borderColor: "rgba(255,255,255,0.18)", backgroundColor: "rgba(8,8,10,0.96)", padding: 15 },
  modalPanelCompact: { width: "100%", maxWidth: 540, borderRadius: 19, borderWidth: 1, borderColor: "rgba(255,54,69,0.36)", backgroundColor: "rgba(8,8,10,0.96)", padding: 16 },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10 },
  modalTitle: { color: "#FFFFFF", fontSize: 17, fontWeight: "900" },
  modalClose: { color: "#FFFFFF", fontSize: 23, padding: 4 },
  modalCloseButton: { width: 36, height: 36, alignItems: "center", justifyContent: "center" },
  modalList: { marginTop: 10 },
  modalListContent: { paddingBottom: 10 },
  modalEmpty: { color: "rgba(225,225,232,0.58)", fontSize: 10, textAlign: "center", marginVertical: 24 },
  notificationRow: { borderRadius: 10, borderWidth: 1, borderColor: "rgba(255,255,255,0.12)", backgroundColor: "rgba(0,0,0,0.18)", padding: 11, marginTop: 7 },
  notificationText: { color: "#EFEFF2", fontSize: 10, lineHeight: 15 },
  notificationDate: { color: "rgba(225,225,232,0.48)", fontSize: 7, marginTop: 5 },
  announcementText: { color: "#FFFFFF", fontSize: 13, lineHeight: 20, marginTop: 15 },
  announcementMeta: { color: "rgba(230,230,236,0.55)", fontSize: 8, marginTop: 13 },
  publicProfileHero: { flexDirection: "row", alignItems: "center", gap: 13, marginTop: 14 },
  publicProfileCounts: { color: "rgba(240,240,244,0.66)", fontSize: 9, marginTop: 12 }
});
