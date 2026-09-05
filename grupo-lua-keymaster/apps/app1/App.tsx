import "./mobileReadability";
import { installVersionedApiFetch } from "./appVersion";

declare const require: (path: string) => { default: React.ComponentType };

installVersionedApiFetch();
const AppCompatibilityGate = require("./AppCompatibilityGate").default;

export default AppCompatibilityGate;
