import "expo-status-bar";
import type { ReactElement } from "react";

declare module "expo-status-bar" {
  function StatusBar(props: {
    style?: "auto" | "inverted" | "light" | "dark";
    hidden?: boolean;
    animated?: boolean;
    translucent?: boolean;
    backgroundColor?: string;
  }): ReactElement | null;
}
