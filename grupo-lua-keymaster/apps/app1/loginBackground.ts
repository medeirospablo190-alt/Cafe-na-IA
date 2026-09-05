import { Image } from "react-native";

declare const require: (path: string) => number;

// Arte escolhida para o login do App 1. Mantida como asset físico no bundle Android/iOS
// para evitar falhas de renderização causadas por Data URI/Base64 grande.
const LOGIN_BACKGROUND_ASSET = require("./assets/login-background.jpg");

export const LOGIN_BACKGROUND_DATA_URI = Image.resolveAssetSource(LOGIN_BACKGROUND_ASSET).uri;
