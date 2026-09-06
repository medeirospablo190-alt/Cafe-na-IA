import bg0 from "./backgroundData/bg0";
import bg1 from "./backgroundData/bg1";
import bg2 from "./backgroundData/bg2";
import bg3 from "./backgroundData/bg3";
import bg4 from "./backgroundData/bg4";
import bg5 from "./backgroundData/bg5";

// Fundo global aprovado para o App 1. Dividido em partes pequenas para manter
// o módulo legível e evitar uma única constante muito grande no código-fonte.
export const LOGIN_BACKGROUND_DATA_URI =
  `data:image/jpeg;base64,${bg0}${bg1}${bg2}${bg3}${bg4}${bg5}`;
