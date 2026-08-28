const state = {
  files: [],
  diagnostics: [],
  diagnosticFilter: "all",
  diagnosticTimer: null
};

function $(id) {
  return document.getElementById(id);
}

function showToast(message) {
  const toast = $("toast");

  if (!toast) return;

  toast.textContent = String(message || "");
  toast.classList.add("show");

  clearTimeout(
    window.__cafeinaToast
  );

  window.__cafeinaToast =
    setTimeout(() => {
      toast.classList.remove(
        "show"
      );
    }, 2200);
}

function formatBytes(bytes) {
  let value =
    Number(bytes || 0);

  if (
    !Number.isFinite(value) ||
    value <= 0
  ) {
    return "0 B";
  }

  const units = [
    "B",
    "KB",
    "MB",
    "GB"
  ];

  let unit = 0;

  while (
    value >= 1024 &&
    unit < units.length - 1
  ) {
    value /= 1024;
    unit++;
  }

  return (
    value.toFixed(
      unit === 0 ? 0 : 1
    ) +
    " " +
    units[unit]
  );
}

function formatDate(value) {
  if (!value) return "—";

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return "—";
  }

  return date.toLocaleString(
    "pt-BR"
  );
}

function formatTime(value) {
  if (!value) return "—";

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return "—";
  }

  return date.toLocaleTimeString(
    "pt-BR",
    {
      hour: "2-digit",
      minute: "2-digit"
    }
  );
}

function setBadge(id, number) {
  const badge = $(id);

  if (!badge) return;

  const count =
    Number(number || 0);

  badge.textContent =
    String(count);

  badge.classList.toggle(
    "hidden",
    count <= 0
  );
}

/* ==========================================================
   NAVEGAÇÃO
   ========================================================== */

function openPage(name) {
  document
    .querySelectorAll(".page")
    .forEach(page => {
      page.classList.remove(
        "active"
      );
    });

  const page =
    $(`page-${name}`);

  if (!page) return;

  page.classList.add(
    "active"
  );

  document
    .querySelectorAll(
      "[data-page]"
    )
    .forEach(button => {
      button.classList.toggle(
        "active",
        button.dataset.page === name
      );
    });

  if (name === "files") {
    loadFiles();
  }

  if (name === "diagnostics") {
    loadDiagnostics();
    startDiagnosticPolling();
  } else {
    stopDiagnosticPolling();
  }

  if (name === "status") {
    checkHealth();
  }

  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
}

function bindNavigation() {
  document
    .querySelectorAll(
      "[data-page]"
    )
    .forEach(button => {
      button.addEventListener(
        "click",
        () => {
          openPage(
            button.dataset.page
          );
        }
      );
    });

  document
    .querySelectorAll(
      "[data-open-page]"
    )
    .forEach(button => {
      button.addEventListener(
        "click",
        () => {
          openPage(
            button.dataset
              .openPage
          );
        }
      );
    });
}

/* ==========================================================
   STATUS
   ========================================================== */

async function checkHealth() {
  const dot =
    $("headerStatusDot");

  const header =
    $("headerStatusText");

  try {
    const response =
      await fetch(
        "/health",
        {
          cache: "no-store"
        }
      );

    if (!response.ok) {
      throw new Error(
        `HTTP ${response.status}`
      );
    }

    const data =
      await response.json();

    if (dot) {
      dot.className =
        "status-dot online";
    }

    if (header) {
      header.textContent =
        "Servidor online";
    }

    if ($("homeServerStatus")) {
      $("homeServerStatus")
        .textContent =
        "Online";
    }

    if ($("statusServer")) {
      $("statusServer")
        .textContent =
        "Online";
    }

    if ($("statusFiles")) {
      $("statusFiles")
        .textContent =
        data.files === true
          ? "Disponível"
          : "Verificar";
    }

    try {
      const diag =
        await fetch(
          "/api/diagnostics",
          {
            cache: "no-store"
          }
        );

      if ($("statusDiagnostics")) {
        $("statusDiagnostics")
          .textContent =
          diag.ok
            ? "Disponível"
            : "Indisponível";
      }

    } catch {
      if ($("statusDiagnostics")) {
        $("statusDiagnostics")
          .textContent =
          "Indisponível";
      }
    }

  } catch {
    if (dot) {
      dot.className =
        "status-dot offline";
    }

    if (header) {
      header.textContent =
        "Servidor offline";
    }

    if ($("homeServerStatus")) {
      $("homeServerStatus")
        .textContent =
        "Offline";
    }

    if ($("statusServer")) {
      $("statusServer")
        .textContent =
        "Offline";
    }
  }
}

/* ==========================================================
   ARQUIVOS
   ========================================================== */

async function loadFiles() {
  const list =
    $("filesList");

  if (!list) return;

  list.innerHTML = `
    <div class="state-card">
      <div class="state-icon">...</div>
      <strong>Carregando</strong>
      <span>Consultando arquivos.</span>
    </div>
  `;

  try {
    const response =
      await fetch(
        "/api/files",
        {
          cache: "no-store"
        }
      );

    if (!response.ok) {
      throw new Error(
        `HTTP ${response.status}`
      );
    }

    const data =
      await response.json();

    const files =
      Array.isArray(data.files)
        ? data.files
        : [];

    state.files =
      files;

    const total =
      files.reduce(
        (sum, file) =>
          sum +
          Number(
            file.bytes ||
            file.size ||
            0
          ),
        0
      );

    if ($("filesCount")) {
      $("filesCount")
        .textContent =
        `${files.length} arquivos`;
    }

    if ($("filesSize")) {
      $("filesSize")
        .textContent =
        formatBytes(total);
    }

    if ($("filesUpdatedAt")) {
      $("filesUpdatedAt")
        .textContent =
        formatTime(
          new Date()
        );
    }

    if ($("homeFilesCount")) {
      $("homeFilesCount")
        .textContent =
        String(files.length);
    }

    setBadge(
      "filesNavBadge",
      files.length
    );

    list.innerHTML = "";

    if (!files.length) {
      list.innerHTML = `
        <div class="state-card">
          <div class="state-icon">✓</div>
          <strong>Nenhum arquivo</strong>
          <span>Nenhum arquivo armazenado no momento.</span>
        </div>
      `;

      return;
    }

    files.forEach(file => {
      list.appendChild(
        createFileCard(file)
      );
    });

  } catch (error) {
    list.innerHTML = "";

    const card =
      document.createElement(
        "div"
      );

    card.className =
      "state-card";

    const icon =
      document.createElement(
        "div"
      );

    icon.className =
      "state-icon";

    icon.textContent = "!";

    const title =
      document.createElement(
        "strong"
      );

    title.textContent =
      "Erro ao carregar arquivos";

    const text =
      document.createElement(
        "span"
      );

    text.textContent =
      error.message;

    card.append(
      icon,
      title,
      text
    );

    list.appendChild(card);
  }
}

function createFileCard(file) {
  const name =
    String(
      file.name ||
      file.filename ||
      "arquivo"
    );

  const relative =
    file.downloadUrl ||
    `/files/${encodeURIComponent(name)}`;

  const url =
    new URL(
      relative,
      window.location.origin
    ).href;

  const card =
    document.createElement(
      "article"
    );

  card.className =
    "file-card";

  const icon =
    document.createElement(
      "div"
    );

  icon.className =
    "file-icon";

  icon.textContent =
    "▱";

  const main =
    document.createElement(
      "div"
    );

  main.className =
    "file-main";

  const title =
    document.createElement(
      "div"
    );

  title.className =
    "file-name";

  title.textContent =
    name;

  const meta =
    document.createElement(
      "div"
    );

  meta.className =
    "file-meta";

  meta.textContent =
    formatBytes(
      file.bytes ||
      file.size
    );

  main.append(
    title,
    meta
  );

  const actions =
    document.createElement(
      "div"
    );

  actions.className =
    "file-actions";

  const copy =
    document.createElement(
      "button"
    );

  copy.className =
    "file-action";

  copy.textContent =
    "Copiar";

  copy.onclick =
    () => copyText(
      url,
      "Link copiado"
    );

  const download =
    document.createElement(
      "button"
    );

  download.className =
    "file-action download";

  download.textContent =
    "Baixar";

  download.onclick =
    () => {
      window.location.href =
        url;
    };

  actions.append(
    copy,
    download
  );

  card.append(
    icon,
    main,
    actions
  );

  return card;
}

/* ==========================================================
   DIAGNÓSTICO
   ========================================================== */

function diagnosticType(type) {
  const labels = {
    compile:
      "Compilação",

    runtime:
      "Runtime",

    "async-runtime":
      "Assíncrono",

    http:
      "HTTP"
  };

  return (
    labels[
      String(
        type || ""
      ).toLowerCase()
    ] ||
    type ||
    "Desconhecido"
  );
}

function scriptName(item) {
  if (item.scriptName) {
    return item.scriptName;
  }

  if (item.script) {
    return item.script;
  }

  if (item.scriptUrl) {
    const parts =
      String(
        item.scriptUrl
      ).split("/");

    return (
      parts[
        parts.length - 1
      ] ||
      "Desconhecido"
    );
  }

  return "Desconhecido";
}

async function loadDiagnostics() {
  try {
    const response =
      await fetch(
        "/api/diagnostics",
        {
          cache: "no-store"
        }
      );

    if (!response.ok) {
      throw new Error(
        `HTTP ${response.status}`
      );
    }

    const data =
      await response.json();

    let diagnostics =
      Array.isArray(
        data.diagnostics
      )
        ? data.diagnostics
        : [];

    diagnostics =
      diagnostics
        .slice()
        .reverse();

    state.diagnostics =
      diagnostics;

    updateDiagnosticHeader();

    renderDiagnostics();

  } catch (error) {
    const status =
      $("diagnosticStatus");

    const description =
      $("diagnosticStatusDescription");

    if (status) {
      status.textContent =
        "API indisponível";
    }

    if (description) {
      description.textContent =
        `Não foi possível consultar /api/diagnostics. ${error.message}`;
    }

    const list =
      $("diagnosticsList");

    if (list) {
      list.innerHTML = `
        <div class="state-card">
          <div class="state-icon">!</div>
          <strong>Diagnóstico indisponível</strong>
          <span>Verifique o server.js e a rota /api/diagnostics.</span>
        </div>
      `;
    }
  }
}

function updateDiagnosticHeader() {
  const total =
    state.diagnostics.length;

  const latest =
    state.diagnostics[0];

  const status =
    $("diagnosticStatus");

  const description =
    $("diagnosticStatusDescription");

  if (total === 0) {
    if (status) {
      status.textContent =
        "Aguardando erros";
    }

    if (description) {
      description.textContent =
        "A API está online. Nenhum erro foi recebido.";
    }
  } else {
    if (status) {
      status.textContent =
        "Erro detectado";
    }

    if (description) {
      description.textContent =
        "Há diagnósticos disponíveis para análise.";
    }
  }

  if ($("diagnosticsCount")) {
    $("diagnosticsCount")
      .textContent =
      String(total);
  }

  if ($("diagnosticsLastType")) {
    $("diagnosticsLastType")
      .textContent =
      latest
        ? diagnosticType(
            latest.type
          )
        : "Nenhum";
  }

  if ($("diagnosticsUpdatedAt")) {
    $("diagnosticsUpdatedAt")
      .textContent =
      formatTime(
        new Date()
      );
  }

  if ($("homeDiagnosticsCount")) {
    $("homeDiagnosticsCount")
      .textContent =
      String(total);
  }

  setBadge(
    "diagnosticsNavBadge",
    total
  );
}

function renderDiagnostics() {
  const list =
    $("diagnosticsList");

  if (!list) return;

  const filtered =
    state.diagnostics
      .filter(item => {

        if (
          state.diagnosticFilter ===
          "all"
        ) {
          return true;
        }

        return (
          String(
            item.type || ""
          ).toLowerCase() ===
          state.diagnosticFilter
        );
      });

  list.innerHTML = "";

  if (!filtered.length) {
    list.innerHTML = `
      <div class="state-card">
        <div class="state-icon">✓</div>
        <strong>Nenhum erro</strong>
        <span>Aguardando um diagnóstico do Loader.</span>
      </div>
    `;

    return;
  }

  filtered.forEach(item => {
    list.appendChild(
      createDiagnosticCard(item)
    );
  });
}

function createDiagnosticCard(item) {
  const card =
    document.createElement(
      "article"
    );

  card.className =
    "diagnostic-card";

  const head =
    document.createElement(
      "div"
    );

  head.className =
    "diagnostic-head";

  const typeWrap =
    document.createElement(
      "div"
    );

  typeWrap.className =
    "diagnostic-type-wrap";

  const dot =
    document.createElement(
      "span"
    );

  dot.className =
    "diagnostic-severity";

  const type =
    document.createElement(
      "span"
    );

  type.className =
    "diagnostic-type";

  type.textContent =
    diagnosticType(
      item.type
    );

  typeWrap.append(
    dot,
    type
  );

  const date =
    document.createElement(
      "span"
    );

  date.className =
    "diagnostic-time";

  date.textContent =
    formatDate(
      item.receivedAt ||
      item.clientTime
    );

  head.append(
    typeWrap,
    date
  );

  const body =
    document.createElement(
      "div"
    );

  body.className =
    "diagnostic-body";

  const script =
    document.createElement(
      "div"
    );

  script.className =
    "diagnostic-script";

  script.textContent =
    `SCRIPT • ${scriptName(item)}`;

  const message =
    document.createElement(
      "div"
    );

  message.className =
    "diagnostic-message";

  message.textContent =
    item.message ||
    "Sem mensagem";

  const meta =
    document.createElement(
      "div"
    );

  meta.className =
    "diagnostic-meta";

  [
    ["Versão", item.version],
    ["PlaceId", item.placeId],
    ["GameId", item.gameId],
    ["Executor", item.executor]
  ].forEach(
    ([label, value]) => {
      if (!value) return;

      const pill =
        document.createElement(
          "span"
        );

      pill.className =
        "meta-pill";

      pill.textContent =
        `${label}: ${value}`;

      meta.appendChild(pill);
    }
  );

  body.append(
    script,
    message,
    meta
  );

  if (item.trace) {
    const traceTitle =
      document.createElement(
        "div"
      );

    traceTitle.className =
      "trace-title";

    traceTitle.textContent =
      "TRACE";

    const trace =
      document.createElement(
        "div"
      );

    trace.className =
      "trace-box";

    trace.textContent =
      item.trace;

    body.append(
      traceTitle,
      trace
    );
  }

  const actions =
    document.createElement(
      "div"
    );

  actions.className =
    "diagnostic-actions";

  const copy =
    document.createElement(
      "button"
    );

  copy.className =
    "button primary";

  copy.textContent =
    "Copiar este erro";

  copy.onclick =
    () => {
      copyText(
        buildDiagnostic(item),
        "Diagnóstico copiado"
      );
    };

  actions.appendChild(copy);

  body.appendChild(actions);

  card.append(
    head,
    body
  );

  return card;
}

function buildDiagnostic(item) {
  return [
    "CAFEÍNA - DIAGNÓSTICO",
    "",
    `Script: ${scriptName(item)}`,
    `Tipo: ${diagnosticType(item.type)}`,
    `Mensagem: ${item.message || "—"}`,
    `Versão: ${item.version || "—"}`,
    `PlaceId: ${item.placeId || "—"}`,
    `GameId: ${item.gameId || "—"}`,
    `Executor: ${item.executor || "—"}`,
    `Horário: ${formatDate(item.receivedAt || item.clientTime)}`,
    "",
    "TRACE:",
    item.trace ||
      "Nenhum trace disponível."
  ].join("\n");
}

async function copyAllDiagnostics() {
  if (
    !state.diagnostics.length
  ) {
    showToast(
      "Nenhum diagnóstico disponível"
    );

    return;
  }

  const text =
    state.diagnostics
      .map(buildDiagnostic)
      .join(
        "\n\n--------------------\n\n"
      );

  copyText(
    text,
    "Diagnósticos copiados"
  );
}

async function copyText(
  text,
  successMessage
) {
  try {
    await navigator
      .clipboard
      .writeText(text);

    showToast(
      successMessage ||
      "Copiado"
    );

  } catch {
    window.prompt(
      "Copie:",
      text
    );
  }
}

async function clearDiagnostics() {
  if (
    !confirm(
      "Limpar todos os diagnósticos?"
    )
  ) {
    return;
  }

  try {
    const response =
      await fetch(
        "/api/diagnostics",
        {
          method: "DELETE",
          credentials: "same-origin"
        }
      );

    if (!response.ok) {
      throw new Error(
        `HTTP ${response.status}`
      );
    }

    showToast(
      "Diagnósticos limpos"
    );

    loadDiagnostics();

  } catch (error) {
    showToast(
      `Não foi possível limpar: ${error.message}`
    );
  }
}

/* ==========================================================
   FILTROS
   ========================================================== */

function bindFilters() {
  document
    .querySelectorAll(
      "[data-diagnostic-filter]"
    )
    .forEach(button => {

      button.addEventListener(
        "click",
        () => {

          state.diagnosticFilter =
            button.dataset
              .diagnosticFilter;

          document
            .querySelectorAll(
              "[data-diagnostic-filter]"
            )
            .forEach(item => {
              item.classList.toggle(
                "active",
                item === button
              );
            });

          renderDiagnostics();
        }
      );
    });
}

/* ==========================================================
   POLLING
   ========================================================== */

function startDiagnosticPolling() {
  stopDiagnosticPolling();

  state.diagnosticTimer =
    setInterval(() => {

      const page =
        $("page-diagnostics");

      if (
        page &&
        page.classList.contains(
          "active"
        )
      ) {
        loadDiagnostics();
      }

    }, 3000);
}

function stopDiagnosticPolling() {
  if (
    state.diagnosticTimer
  ) {
    clearInterval(
      state.diagnosticTimer
    );

    state.diagnosticTimer =
      null;
  }
}

/* ==========================================================
   EVENTS
   ========================================================== */

function bindButtons() {
  $("refreshFilesButton")
    ?.addEventListener(
      "click",
      loadFiles
    );

  $("refreshDiagnosticsButton")
    ?.addEventListener(
      "click",
      loadDiagnostics
    );

  $("copyAllDiagnosticsButton")
    ?.addEventListener(
      "click",
      copyAllDiagnostics
    );

  $("clearDiagnosticsButton")
    ?.addEventListener(
      "click",
      clearDiagnostics
    );

  $("refreshHealthButton")
    ?.addEventListener(
      "click",
      checkHealth
    );
}

async function start() {
  bindNavigation();
  bindButtons();
  bindFilters();

  await Promise.allSettled([
    checkHealth(),
    loadFiles(),
    loadDiagnostics()
  ]);
}

document.addEventListener(
  "DOMContentLoaded",
  start
);
