// Stable entrypoint for Render configurations that still run `node server.js`.
// The download portal itself lives in portal-main.js and is spawned internally
// by gateway-main.js, so every public entrypoint exposes the same collector routes.
import "./gateway-main.js";
