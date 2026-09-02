import express from "express";
import { registerMenuRoutes } from "./menu-routes.js";

const originalUse = express.application.use;
const registered = Symbol("grupo-lua-menu-routes-registered");

express.application.use = function patchedUse(...args) {
  const addingErrorHandler = args.some((entry) => typeof entry === "function" && entry.length === 4);
  if (addingErrorHandler && !this[registered]) {
    this[registered] = true;
    registerMenuRoutes(this);
  }
  return originalUse.apply(this, args);
};

try {
  await import("./server.js");
} finally {
  express.application.use = originalUse;
}
