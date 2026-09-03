import { Platform } from "react-native";
import * as Application from "expo-application";
import * as Crypto from "expo-crypto";
import * as SecureStore from "expo-secure-store";

const INSTALLATION_ID_KEY = "grupo-lua-app1-installation-id-v1";

export type App1DeviceIdentity = {
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

export async function getApp1DeviceIdentity(): Promise<App1DeviceIdentity> {
  const platform = Platform.OS === "android" ? "android" : Platform.OS === "ios" ? "ios" : "unknown";
  let nativeDeviceId = "";
  if (Platform.OS === "android") {
    nativeDeviceId = Application.getAndroidId();
  } else if (Platform.OS === "ios") {
    nativeDeviceId = (await Application.getIosIdForVendorAsync()) || "";
  }

  return {
    platform,
    nativeDeviceId,
    installationId: await getInstallationId(),
    integrityKeyId: "",
    integrityProof: null
  };
}
