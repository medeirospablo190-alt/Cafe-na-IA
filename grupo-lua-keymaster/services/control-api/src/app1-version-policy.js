const DEFAULT_APP1_VERSION = "0.3.2";

export function parseAppVersion(value) {
  const text = String(value || "").trim();
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(text);
  if (!match) return null;
  return match.slice(1).map((part) => Number(part));
}

export function compareAppVersions(left, right) {
  const a = Array.isArray(left) ? left : parseAppVersion(left);
  const b = Array.isArray(right) ? right : parseAppVersion(right);
  if (!a || !b) return null;
  for (let index = 0; index < 3; index += 1) {
    if (a[index] < b[index]) return -1;
    if (a[index] > b[index]) return 1;
  }
  return 0;
}

function normalizedVersion(value, fallback) {
  const text = String(value || "").trim();
  return parseAppVersion(text) ? text : fallback;
}

export function resolveApp1VersionPolicy(env = process.env) {
  const minSupportedVersion = normalizedVersion(env.APP1_MIN_SUPPORTED_VERSION, DEFAULT_APP1_VERSION);
  let latestVersion = normalizedVersion(env.APP1_LATEST_VERSION, minSupportedVersion);
  if (compareAppVersions(latestVersion, minSupportedVersion) < 0) latestVersion = minSupportedVersion;

  return {
    minSupportedVersion,
    latestVersion,
    headerRequired: String(env.APP1_VERSION_HEADER_REQUIRED || "false").toLowerCase() === "true"
  };
}

export function evaluateApp1Version(version, policy = resolveApp1VersionPolicy()) {
  const currentVersion = String(version || "").trim();
  if (!parseAppVersion(currentVersion)) {
    return {
      status: "INVALID_VERSION",
      currentVersion,
      updateRequired: false,
      updateAvailable: false
    };
  }

  if (compareAppVersions(currentVersion, policy.minSupportedVersion) < 0) {
    return {
      status: "UPDATE_REQUIRED",
      currentVersion,
      updateRequired: true,
      updateAvailable: true
    };
  }

  if (compareAppVersions(currentVersion, policy.latestVersion) < 0) {
    return {
      status: "UPDATE_AVAILABLE",
      currentVersion,
      updateRequired: false,
      updateAvailable: true
    };
  }

  return {
    status: "COMPATIBLE",
    currentVersion,
    updateRequired: false,
    updateAvailable: false
  };
}

function messageFor(result, policy) {
  if (result.status === "UPDATE_REQUIRED") {
    return `Esta versão do GRUPO LUA é antiga demais. Atualize para ${policy.minSupportedVersion} ou superior para continuar.`;
  }
  if (result.status === "UPDATE_AVAILABLE") {
    return `Existe uma versão mais nova do GRUPO LUA (${policy.latestVersion}). Você pode continuar usando esta versão por enquanto.`;
  }
  if (result.status === "INVALID_VERSION") {
    return "O aplicativo não informou uma versão válida.";
  }
  return "Esta versão do GRUPO LUA é compatível com a Control API.";
}

function setPolicyHeaders(res, policy, status = "UNKNOWN") {
  res.setHeader("X-Grupo-Lua-Min-Version", policy.minSupportedVersion);
  res.setHeader("X-Grupo-Lua-Latest-Version", policy.latestVersion);
  res.setHeader("X-Grupo-Lua-Update-Status", status);
}

function sendJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.end(JSON.stringify(body));
}

export function handleApp1VersionPolicy(req, res) {
  const requestUrl = new URL(String(req.url || "/"), "http://grupo-lua.local");
  if (!requestUrl.pathname.startsWith("/v1/app1/")) return false;

  const policy = resolveApp1VersionPolicy();
  const headerVersion = String(req.headers?.["x-grupo-lua-app-version"] || "").trim();

  if (requestUrl.pathname === "/v1/app1/compatibility") {
    if (String(req.method || "GET").toUpperCase() !== "GET") {
      setPolicyHeaders(res, policy, "METHOD_NOT_ALLOWED");
      sendJson(res, 405, {
        ok: false,
        code: "METHOD_NOT_ALLOWED",
        message: "Use GET para consultar a compatibilidade do App 1."
      });
      return true;
    }

    const requestedVersion = String(requestUrl.searchParams.get("version") || headerVersion || "").trim();
    const platform = String(requestUrl.searchParams.get("platform") || req.headers?.["x-grupo-lua-platform"] || "unknown").slice(0, 24);
    const result = evaluateApp1Version(requestedVersion, policy);
    setPolicyHeaders(res, policy, result.status);

    const statusCode = result.status === "INVALID_VERSION" ? 400 : 200;
    sendJson(res, statusCode, {
      ok: result.status !== "INVALID_VERSION",
      app: "APP1",
      platform,
      currentVersion: result.currentVersion,
      minSupportedVersion: policy.minSupportedVersion,
      latestVersion: policy.latestVersion,
      status: result.status,
      updateRequired: result.updateRequired,
      updateAvailable: result.updateAvailable,
      message: messageFor(result, policy),
      serverTime: new Date().toISOString()
    });
    return true;
  }

  if (!headerVersion) {
    setPolicyHeaders(res, policy, "VERSION_NOT_PROVIDED");
    if (!policy.headerRequired) return false;
    sendJson(res, 426, {
      ok: false,
      code: "APP_VERSION_REQUIRED",
      message: "Atualize o GRUPO LUA para uma versão que informe compatibilidade com o servidor.",
      minSupportedVersion: policy.minSupportedVersion,
      latestVersion: policy.latestVersion
    });
    return true;
  }

  const result = evaluateApp1Version(headerVersion, policy);
  setPolicyHeaders(res, policy, result.status);

  if (result.status === "INVALID_VERSION") {
    sendJson(res, 400, {
      ok: false,
      code: "INVALID_APP_VERSION",
      message: messageFor(result, policy)
    });
    return true;
  }

  if (result.updateRequired) {
    sendJson(res, 426, {
      ok: false,
      code: "APP_UPDATE_REQUIRED",
      message: messageFor(result, policy),
      currentVersion: result.currentVersion,
      minSupportedVersion: policy.minSupportedVersion,
      latestVersion: policy.latestVersion
    });
    return true;
  }

  return false;
}
