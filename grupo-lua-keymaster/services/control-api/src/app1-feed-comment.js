export const APP1_FEED_COMMENT_MAX_CHARS = 500;

export function normalizeFeedComment(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .replace(/\r\n?/g, "\n")
    .trim();
}

export function validateFeedComment(value) {
  const comment = normalizeFeedComment(value);
  if (!comment) return { ok: true, comment: null };

  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(comment)) {
    return {
      ok: false,
      code: "COMMENT_INVALID_CHARS",
      message: "O comentário contém caracteres de controle não permitidos."
    };
  }

  const chars = Array.from(comment).length;
  if (chars > APP1_FEED_COMMENT_MAX_CHARS) {
    return {
      ok: false,
      code: "COMMENT_TOO_LONG",
      message: `O comentário pode ter no máximo ${APP1_FEED_COMMENT_MAX_CHARS} caracteres.`
    };
  }

  return { ok: true, comment };
}
