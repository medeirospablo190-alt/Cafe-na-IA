import "./mobileReadability";

declare const require: (path: string) => { default: React.ComponentType };

const AppRoot = require("./AppRoot").default;

export default AppRoot;
