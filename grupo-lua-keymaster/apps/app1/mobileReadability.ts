import { StyleSheet } from "react-native";

type MutableStyle = Record<string, unknown> & {
  fontSize?: number;
  lineHeight?: number;
  minHeight?: number;
};

type StyleMap = Record<string, MutableStyle>;

const FONT_MINIMUMS: Record<string, number> = {
  byline: 10,
  eyebrowLight: 11,
  loginHelp: 13,
  loginError: 12,
  primaryButtonText: 13,
  textButtonLabel: 10,
  eyebrow: 10,
  paragraph: 13,
  counter: 10,
  error: 12,
  warningEyebrow: 12,
  termTitle: 14,
  termEmphasis: 12,
  checkText: 12,
  publicName: 14,
  devBadge: 9,
  sessionLine: 10,
  heroKicker: 10,
  featureTitle: 13,
  featureText: 11,
  segmentText: 10,
  navText: 10,

  heroText: 11,
  primaryMiniText: 10,
  chipText: 10,
  ok: 10,
  warn: 10,
  sourceBadge: 9,
  legacyBadge: 9,
  kindBadge: 9,
  cardTitle: 15,
  meta: 10,
  warnMeta: 10,
  secretHint: 11,
  actionText: 10,
  emptyTitle: 14,
  emptyText: 11,
  backText: 10,
  detailTitle: 16,
  iconButtonText: 10,
  suspendedTitle: 13,
  suspendedText: 10,
  noticeButtonText: 10,
  statValue: 14,
  statLabel: 9,
  modalEyebrow: 10,
  modalTitle: 20,
  label: 10,
  input: 13,
  codeInput: 12,
  help: 10,
  importButtonText: 10,
  saveButtonText: 11,
  dangerButtonText: 11,
  cancelText: 10,
  secretValue: 13
};

const HEIGHT_MINIMUMS: Record<string, number> = {
  primaryButton: 52,
  textButton: 44,
  segmentItem: 44,
  primaryMini: 44,
  chip: 44,
  action: 44,
  backButton: 44,
  iconButton: 44,
  noticeButton: 44,
  importButton: 44,
  saveButton: 50,
  dangerButton: 50,
  cancelButton: 44
};

const patchedStyleSheet = StyleSheet as typeof StyleSheet & {
  __grupoLuaMobileReadability?: boolean;
};

if (!patchedStyleSheet.__grupoLuaMobileReadability) {
  const originalCreate = StyleSheet.create;

  (patchedStyleSheet as unknown as { create: (styles: StyleMap) => unknown }).create = (styles: StyleMap) => {
    const adjusted: StyleMap = {};

    for (const [name, source] of Object.entries(styles)) {
      const style = { ...source };
      const minimumFont = FONT_MINIMUMS[name];
      const minimumHeight = HEIGHT_MINIMUMS[name];

      if (minimumFont && (typeof style.fontSize !== "number" || style.fontSize < minimumFont)) {
        style.fontSize = minimumFont;
      }

      if (minimumHeight && (typeof style.minHeight !== "number" || style.minHeight < minimumHeight)) {
        style.minHeight = minimumHeight;
      }

      if (
        typeof style.fontSize === "number" &&
        typeof style.lineHeight === "number" &&
        style.lineHeight < style.fontSize + 4
      ) {
        style.lineHeight = style.fontSize + 4;
      }

      adjusted[name] = style;
    }

    return originalCreate(adjusted as never);
  };

  patchedStyleSheet.__grupoLuaMobileReadability = true;
}
