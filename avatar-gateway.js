// Compatibility entrypoint kept for Render configurations that still run
// `node avatar-gateway.js` directly. The actual gateway now lives in one
// implementation so avatar, geometry, inventory trace and portal proxying
// cannot drift apart.
import "./gateway-main.js";
