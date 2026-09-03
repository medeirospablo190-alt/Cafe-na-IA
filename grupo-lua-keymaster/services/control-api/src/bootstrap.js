import http from "node:http";

const ALLOWED_BROWSER_ORIGINS = new Set([
  "https://hoppscotch.io"
]);

function appendVary(res, value) {
  const current = res.getHeader("Vary");
  if (!current) {
    res.setHeader("Vary", value);
    return;
  }
  const values = String(current)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (!values.includes(value)) values.push(value);
  res.setHeader("Vary", values.join(", "));
}

function applyCors(req, res) {
  const origin = String(req.headers.origin || "");
  if (!ALLOWED_BROWSER_ORIGINS.has(origin)) return false;

  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Access-Control-Max-Age", "600");
  appendVary(res, "Origin");
  return true;
}

const originalCreateServer = http.createServer;
http.createServer = function patchedCreateServer(...args) {
  const listenerIndex = args.findIndex((arg) => typeof arg === "function");
  if (listenerIndex >= 0) {
    const originalListener = args[listenerIndex];
    args[listenerIndex] = (req, res) => {
      const allowed = applyCors(req, res);
      if (allowed && req.method === "OPTIONS") {
        res.statusCode = 204;
        res.end();
        return;
      }
      originalListener(req, res);
    };
  }
  return originalCreateServer.apply(this, args);
};

await import("./server.js");
