import { Platform } from "react-native";
import * as Application from "expo-application";
import * as Crypto from "expo-crypto";
import * as SecureStore from "expo-secure-store";

const INSTALLATION_ID_KEY = "km_installation_id_v1";

export type DeviceIdentity = {
  platform: "android" | "ios" | "unknown";
  nativeDeviceId: string;
  installationId: string;
  integrityKeyId: string;
  integrityProof: string | null;
};

async function getInstallationId() {
  let value = await SecureStore.getItemAsync(INSTALLATION_ID_KEY);
  if (!value) {
    value = Crypto.randomUUID();
    await SecureStore.setItemAsync(INSTALLATION_ID_KEY, value, {
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY
    });
  }
  return value;
}

export async function getDeviceIdentity(): Promise<DeviceIdentity> {
  const platform = Platform.OS === "android" ? "android" : Platform.OS === "ios" ? "ios" : "unknown";
  let nativeDeviceId = "";
  if (Platform.OS === "android") {
    nativeDeviceId = Application.getAndroidId();
  } else if (Platform.OS === "ios") {
    nativeDeviceId = (await Application.getIosIdForVendorAsync()) || "";
  }

  // A prova de Play Integrity/App Attest será preenchida pelo módulo de integridade
  // quando as credenciais Google/Apple do app de produção estiverem configuradas.
  // O backend suporta report/enforce para que isso nunca precise ser decidido pelo cliente.
  return {
    platform,
    nativeDeviceId,
    installationId: await getInstallationId(),
    integrityKeyId: "",
    integrityProof: null
  };
}
