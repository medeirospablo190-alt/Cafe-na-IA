import * as LocalAuthentication from "expo-local-authentication";
import * as SecureStore from "expo-secure-store";

const QUICK_UNLOCK_KEY = "grupo-lua-app1-quick-unlock-v1";

export type QuickUnlockResult =
  | { ok: true }
  | { ok: false; message: string };

export async function isQuickUnlockEnabled() {
  return (await SecureStore.getItemAsync(QUICK_UNLOCK_KEY)) === "1";
}

export async function setQuickUnlockEnabled(enabled: boolean) {
  if (enabled) {
    await SecureStore.setItemAsync(QUICK_UNLOCK_KEY, "1", {
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY
    });
    return;
  }
  await SecureStore.deleteItemAsync(QUICK_UNLOCK_KEY).catch(() => {});
}

export async function authenticateForQuickUnlock(): Promise<QuickUnlockResult> {
  try {
    const result = await LocalAuthentication.authenticateAsync({
      promptMessage: "Abrir GRUPO LUA",
      promptSubtitle: "Confirme sua identidade neste celular",
      promptDescription: "Use a proteção configurada no aparelho para liberar a sessão salva.",
      cancelLabel: "Cancelar",
      fallbackLabel: "Usar senha do aparelho",
      disableDeviceFallback: false,
      requireConfirmation: true
    });

    if (result.success) return { ok: true };

    if (result.error === "user_cancel" || result.error === "system_cancel" || result.error === "app_cancel") {
      return { ok: false, message: "Autenticação cancelada." };
    }
    if (result.error === "not_enrolled" || result.error === "passcode_not_set") {
      return {
        ok: false,
        message: "Este celular ainda não possui uma proteção compatível configurada. Ative biometria ou bloqueio de tela nas configurações do aparelho."
      };
    }
    if (result.error === "lockout") {
      return {
        ok: false,
        message: "A autenticação do aparelho está temporariamente bloqueada por excesso de tentativas. Tente novamente mais tarde ou use o método oferecido pelo sistema."
      };
    }
    if (result.error === "not_available") {
      return {
        ok: false,
        message: "A autenticação local não está disponível neste aparelho."
      };
    }

    return { ok: false, message: "O celular não confirmou sua identidade." };
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : "Não foi possível abrir a autenticação do celular."
    };
  }
}
