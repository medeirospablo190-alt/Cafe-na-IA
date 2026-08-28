const state = {
  files: [],
  diagnostics: [],
  diagnosticFilter: "all",
  diagnosticTimer: null,
  diagnosticsOnline: false
};

// ============================================================
// HELPERS
// ============================================================

function $(id) {
  return document.getElementById(id);
}

function showToast(message) {
  const toast = $("toast");

  if (!toast) {
    console.log("[CAFEÍNA]", message);
    return;
  }

  toast.textContent = String(message || "");
  toast.classList.add("show");

  clearTimeout(window.__cafeinaToastTimer);

  window.__cafeinaToastTimer = setTimeout(() => {
    toast.classList.remove("show");
  }, 2400);
}

function formatBytes(bytes) {
  const number = Number(bytes || 0);

  if (!Number.isFinite(number) || number <= 0) {
    return "0 B";
  }

  const units = [
    "B",
    "KB",
    "MB",
    "GB",
    "TB"
  ];

  let value = number;
  let index = 0;

  while (
    value >= 1024 &&
    index < units.length - 1
  ) {
    value /= 1024;
    index++;
  }

  const decimals =
    index === 0
      ? 0
      : value >= 10
        ? 1
        : 2;

  return `${value.toFixed(decimals)} ${units[index]}`;
}

function formatDate(value) {
  if (!value) {
    return "Data desconhecida";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Data desconhecida";
  }

  return date.toLocaleString("pt-BR");
}

function formatShortTime(value) {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
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

function setBadge(id, count) {
  const badge = $(id);

  if (!badge) {
    return;
  }

  const number = Number(count || 0);

  badge.textContent = String(number);

  badge.classList.toggle(
    "hidden",
    number <= 0
  );
}

function setStatusElement(
  id,
  stateName,
  text
) {
  const el = $(id);

  if (!el) {
    return;
  }

  el.textContent = text;
  el.className = "status-value";

  if (stateName) {
    el.classList.add(stateName);
  }
}

function getDiagnosticDate(item) {
  return (
    item.receivedAt ||
    item.clientTime ||
    item.createdAt ||
    null
  );
}

function getScriptName(item) {
  if (item.scriptName) {
    return String(item.scriptName);
  }

  if (item.script) {
    return String(item.script);
  }

  if (item.scriptUrl) {
    try {
      const url = new URL(item.scriptUrl);

      const parts =
        url.pathname.split("/");

      const name =
        parts[parts.length - 1];

      if (name) {
        return decodeURIComponent(name);
      }
    } catch {
      const parts =
        String(item.scriptUrl).split("/");

      if (parts.length) {
        return parts[parts.length - 1];
      }
    }
  }

  return "Desconhecido";
}

// ============================================================
// NAVEGAÇÃO
// ============================================================

function openPage(pageName) {
  document
    .querySelectorAll(".page")
    .forEach(page => {
      page.classList.remove("active");
    });

  const target =
    $(`page-${pageName}`);

  if (!target) {
    return;
  }

  target.classList.add("active");

  document
    .querySelectorAll("[data-page]")
    .forEach(button => {
      button.classList.toggle(
        "active",
        button.dataset.page === pageName
      );
    });

  if (pageName === "files") {
    loadFiles();
  }

  if (pageName === "diagnostics") {
    ensureDiagnosticsInterface();
    loadDiagnostics();
    startDiagnosticPolling();
  } else {
    stopDiagnosticPolling();
  }

  if (pageName === "status") {
    checkHealth();
  }

  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
}

function bindNavigation() {
  document
    .querySelectorAll("[data-page]")
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
    .querySelectorAll("[data-open-page]")
    .forEach(button => {
      button.addEventListener(
        "click",
        () => {
          openPage(
            button.dataset.openPage
          );
        }
      );
    });
}

// ============================================================
// HEALTH / STATUS
// ============================================================

async function checkHealth() {
  const dot =
    $("headerStatusDot");

  const headerText =
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

    if (headerText) {
      headerText.textContent =
        "Online";
    }

    if ($("homeServerStatus")) {
      $("homeServerStatus")
        .textContent =
        "Online";
    }

    setStatusElement(
      "statusServer",
      "good",
      "Online"
    );

    const filesAvailable =
      data.files === true ||
      data.downloads === true;

    setStatusElement(
      "statusFiles",
      filesAvailable
        ? "good"
        : "warn",
      filesAvailable
        ? "Disponível"
        : "Não informado"
    );

    setStatusElement(
      "statusAI",
      data.ai === true
        ? "good"
        : "warn",
      data.ai === true
        ? "Configurada"
        : "Desativada"
    );

    const aiDescription =
      $("aiDescription");

    if (aiDescription) {
      aiDescription.textContent =
        data.ai === true
          ? "CAFEÍNA AI está configurada e disponível no servidor."
          : "A integração de IA está desativada ou não configurada.";
    }

    try {
      const diagnosticsResponse =
        await fetch(
          "/api/diagnostics",
          {
            cache: "no-store"
          }
        );

      state.diagnosticsOnline =
        diagnosticsResponse.ok;

      setStatusElement(
        "statusDiagnostics",
        diagnosticsResponse.ok
          ? "good"
          : "bad",
        diagnosticsResponse.ok
          ? "Disponível"
          : "Indisponível"
      );

    } catch {
      state.diagnosticsOnline =
        false;

      setStatusElement(
        "statusDiagnostics",
        "bad",
        "Indisponível"
      );
    }

  } catch (error) {
    console.error(
      "HEALTH ERROR:",
      error
    );

    if (dot) {
      dot.className =
        "status-dot offline";
    }

    if (headerText) {
      headerText.textContent =
        "Offline";
    }

    if ($("homeServerStatus")) {
      $("homeServerStatus")
        .textContent =
        "Offline";
    }

    setStatusElement(
      "statusServer",
      "bad",
      "Offline"
    );
  }
}

// ============================================================
// ARQUIVOS
// ============================================================

async function loadFiles() {
  const list =
    $("filesList");

  const count =
    $("filesCount");

  const size =
    $("filesSize");

  const updatedAt =
    $("filesUpdatedAt");

  if (
    !list ||
    !count ||
    !size
  ) {
    return;
  }

  list.innerHTML = `
    <div class="state-card">
      <div class="state-icon">
        ▱
      </div>

      <strong>
        Carregando arquivos...
      </strong>

      <span>
        Consultando o servidor CAFEÍNA.
      </span>
    </div>
  `;

  count.textContent =
    "Carregando...";

  size.textContent =
    "Consultando...";

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

    if (!data.success) {
      throw new Error(
        data.message ||
        "Erro ao consultar arquivos."
      );
    }

    const files =
      Array.isArray(data.files)
        ? data.files
        : [];

    state.files =
      files;

    const totalBytes =
      files.reduce(
        (sum, file) => {
          return (
            sum +
            Number(
              file.bytes ||
              file.size ||
              0
            )
          );
        },
        0
      );

    count.textContent =
      files.length === 1
        ? "1 arquivo"
        : `${files.length} arquivos`;

    size.textContent =
      formatBytes(
        Number(
          data.totalBytes ||
          totalBytes
        )
      );

    if (updatedAt) {
      updatedAt.textContent =
        formatShortTime(
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

    if (files.length === 0) {
      list.innerHTML = `
        <div class="state-card">
          <div class="state-icon">
            ▱
          </div>

          <strong>
            Nenhum arquivo armazenado.
          </strong>

          <span>
            Os relatórios enviados pelo Explorer aparecerão aqui.
          </span>
        </div>
      `;

      return;
    }

    list.innerHTML = "";

    files.forEach(file => {
      list.appendChild(
        createFileCard(file)
      );
    });

  } catch (error) {
    console.error(
      "FILES ERROR:",
      error
    );

    count.textContent = "Erro";
    size.textContent = "Indisponível";

    list.innerHTML = "";

    const errorCard =
      document.createElement("div");

    errorCard.className =
      "state-card error-state";

    const icon =
      document.createElement("div");

    icon.className =
      "state-icon danger";

    icon.textContent = "!";

    const title =
      document.createElement("strong");

    title.textContent =
      "Não foi possível carregar os arquivos.";

    const description =
      document.createElement("span");

    description.textContent =
      error.message ||
      "Erro de conexão.";

    errorCard.append(
      icon,
      title,
      description
    );

    list.appendChild(errorCard);
  }
}

function createFileCard(file) {
  const name =
    String(
      file.name ||
      file.filename ||
      "arquivo"
    );

  const bytes =
    Number(
      file.bytes ||
      file.size ||
      0
    );

  const date =
    file.modifiedAt ||
    file.createdAt;

  const relativeUrl =
    file.downloadUrl ||
    `/files/${encodeURIComponent(name)}`;

  const absoluteUrl =
    new URL(
      relativeUrl,
      window.location.origin
    ).href;

  const card =
    document.createElement("article");

  card.className =
    "file-card";

  const icon =
    document.createElement("div");

  icon.className =
    "file-icon";

  icon.textContent = "▱";

  const main =
    document.createElement("div");

  main.className =
    "file-main";

  const fileName =
    document.createElement("div");

  fileName.className =
    "file-name";

  fileName.textContent =
    name;

  const meta =
    document.createElement("div");

  meta.className =
    "file-meta";

  meta.textContent =
    `${formatBytes(bytes)} • ${formatDate(date)}`;

  main.append(
    fileName,
    meta
  );

  const actions =
    document.createElement("div");

  actions.className =
    "file-actions";

  const copy =
    document.createElement("button");

  copy.className =
    "file-action";

  copy.textContent =
    "Copiar link";

  copy.addEventListener(
    "click",
    async () => {
      try {
        await navigator
          .clipboard
          .writeText(
            absoluteUrl
          );

        showToast(
          "Link copiado."
        );

      } catch {
        window.prompt(
          "Copie o link:",
          absoluteUrl
        );
      }
    }
  );

  const download =
    document.createElement("button");

  download.className =
    "file-action download";

  download.textContent =
    "Baixar";

  download.addEventListener(
    "click",
    () => {
      window.location.href =
        absoluteUrl;
    }
  );

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

// ============================================================
// INTERFACE DE DIAGNÓSTICOS
// Cria automaticamente caso ainda não esteja no index.html.
// ============================================================

function ensureDiagnosticsInterface() {
  const page =
    $("page-diagnostics");

  if (!page) {
    return;
  }

  if (!$("diagnosticControlPanel")) {
    const panel =
      document.createElement("section");

    panel.id =
      "diagnosticControlPanel";

    panel.className =
      "diagnostic-control-panel";

    const summary =
      document.createElement("div");

    summary.className =
      "diagnostic-summary";

    summary.append(
      createDiagnosticSummaryCard(
        "Status",
        "diagnosticStatus",
        "Verificando..."
      ),

      createDiagnosticSummaryCard(
        "Registros",
        "diagnosticsCountLive",
        "0"
      ),

      createDiagnosticSummaryCard(
        "Último erro",
        "diagnosticsLastTypeLive",
        "Nenhum"
      ),

      createDiagnosticSummaryCard(
        "Atualizado",
        "diagnosticsUpdatedAtLive",
        "—"
      )
    );

    const toolbar =
      document.createElement("div");

    toolbar.className =
      "diagnostic-toolbar";

    const copyAll =
      document.createElement("button");

    copyAll.id =
      "copyAllDiagnosticsButton";

    copyAll.className =
      "file-action download";

    copyAll.textContent =
      "📋 Copiar diagnóstico";

    copyAll.addEventListener(
      "click",
      copyAllDiagnostics
    );

    const refresh =
      document.createElement("button");

    refresh.id =
      "refreshDiagnosticsButtonDynamic";

    refresh.className =
      "file-action";

    refresh.textContent =
      "↻ Atualizar";

    refresh.addEventListener(
      "click",
      loadDiagnostics
    );

    const clear =
      document.createElement("button");

    clear.id =
      "clearDiagnosticsButtonDynamic";

    clear.className =
      "file-action";

    clear.textContent =
      "Limpar";

    clear.addEventListener(
      "click",
      clearDiagnostics
    );

    toolbar.append(
      copyAll,
      refresh,
      clear
    );

    panel.append(
      summary,
      toolbar
    );

    const list =
      $("diagnosticsList");

    if (list) {
      page.insertBefore(
        panel,
        list
      );
    } else {
      page.appendChild(panel);

      const newList =
        document.createElement("div");

      newList.id =
        "diagnosticsList";

      page.appendChild(newList);
    }
  }
}

function createDiagnosticSummaryCard(
  label,
  id,
  initialValue
) {
  const card =
    document.createElement("div");

  card.className =
    "summary-card";

  const title =
    document.createElement("span");

  title.textContent =
    label;

  const value =
    document.createElement("strong");

  value.id =
    id;

  value.textContent =
    initialValue;

  card.append(
    title,
    value
  );

  return card;
}

// ============================================================
// DIAGNÓSTICOS
// ============================================================

async function loadDiagnostics() {
  ensureDiagnosticsInterface();

  const list =
    $("diagnosticsList");

  if (!list) {
    return;
  }

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

    if (!data.success) {
      throw new Error(
        data.message ||
        "Erro ao consultar diagnósticos."
      );
    }

    state.diagnosticsOnline =
      true;

    let diagnostics =
      Array.isArray(
        data.diagnostics
      )
        ? data.diagnostics
        : [];

    diagnostics =
      diagnostics
        .slice()
        .sort((a, b) => {
          const aTime =
            new Date(
              getDiagnosticDate(a) || 0
            ).getTime();

          const bTime =
            new Date(
              getDiagnosticDate(b) || 0
            ).getTime();

          return bTime - aTime;
        });

    state.diagnostics =
      diagnostics;

    updateDiagnosticStatus();

    renderDiagnostics();

  } catch (error) {
    console.error(
      "DIAGNOSTICS ERROR:",
      error
    );

    state.diagnosticsOnline =
      false;

    setDiagnosticStatus(
      "API indisponível",
      "bad"
    );

    const count =
      $("diagnosticsCount");

    if (count) {
      count.textContent =
        "Erro";
    }

    const lastType =
      $("diagnosticsLastType");

    if (lastType) {
      lastType.textContent =
        "Indisponível";
    }

    if ($("diagnosticsCountLive")) {
      $("diagnosticsCountLive")
        .textContent =
        "Erro";
    }

    if ($("diagnosticsLastTypeLive")) {
      $("diagnosticsLastTypeLive")
        .textContent =
        "Indisponível";
    }

    list.innerHTML = "";

    const errorCard =
      document.createElement("div");

    errorCard.className =
      "state-card error-state";

    const icon =
      document.createElement("div");

    icon.className =
      "state-icon danger";

    icon.textContent =
      "!";

    const title =
      document.createElement("strong");

    title.textContent =
      "Não foi possível acessar a API de diagnósticos.";

    const description =
      document.createElement("span");

    description.textContent =
      error.message ||
      "Erro de conexão.";

    errorCard.append(
      icon,
      title,
      description
    );

    list.appendChild(
      errorCard
    );
  }
}

function updateDiagnosticStatus() {
  const diagnostics =
    state.diagnostics;

  const total =
    diagnostics.length;

  const latest =
    diagnostics[0] ||
    null;

  if (total === 0) {
    setDiagnosticStatus(
      "Aguardando erros",
      "good"
    );
  } else {
    setDiagnosticStatus(
      "Erro detectado",
      "bad"
    );
  }

  if ($("diagnosticsCount")) {
    $("diagnosticsCount")
      .textContent =
      total === 1
        ? "1 registro"
        : `${total} registros`;
  }

  if ($("diagnosticsCountLive")) {
    $("diagnosticsCountLive")
      .textContent =
      String(total);
  }

  const latestType =
    latest
      ? normalizeDiagnosticType(
          latest.type
        )
      : "Nenhum";

  if ($("diagnosticsLastType")) {
    $("diagnosticsLastType")
      .textContent =
      latestType;
  }

  if ($("diagnosticsLastTypeLive")) {
    $("diagnosticsLastTypeLive")
      .textContent =
      latestType;
  }

  const now =
    new Date();

  if ($("diagnosticsUpdatedAt")) {
    $("diagnosticsUpdatedAt")
      .textContent =
      formatShortTime(now);
  }

  if ($("diagnosticsUpdatedAtLive")) {
    $("diagnosticsUpdatedAtLive")
      .textContent =
      formatShortTime(now);
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

function setDiagnosticStatus(
  text,
  type
) {
  const status =
    $("diagnosticStatus");

  if (!status) {
    return;
  }

  status.textContent =
    text;

  status.className =
    "status-value";

  if (type) {
    status.classList.add(type);
  }
}

function normalizeDiagnosticType(type) {
  const key =
    String(type || "")
      .toLowerCase();

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
    labels[key] ||
    key ||
    "Desconhecido"
  );
}

// ============================================================
// TEXTO PARA COPIAR
// ============================================================

function buildDiagnosticText(item) {
  const lines = [
    "================================",
    "CAFEÍNA - DIAGNÓSTICO DE ERRO",
    "================================",
    "",
    `Script: ${getScriptName(item)}`,
    `Tipo: ${normalizeDiagnosticType(item.type)}`,
    `Mensagem: ${item.message || "Sem mensagem"}`,
    `Versão: ${item.version || "—"}`,
    `PlaceId: ${item.placeId || "—"}`,
    `GameId: ${item.gameId || "—"}`,
    `Executor: ${item.executor || "—"}`,
    `Horário: ${formatDate(getDiagnosticDate(item))}`
  ];

  if (item.scriptUrl) {
    lines.push(
      `URL: ${item.scriptUrl}`
    );
  }

  lines.push(
    "",
    "TRACE:",
    item.trace ||
    "Nenhum trace disponível."
  );

  return lines.join("\n");
}

async function copyText(text) {
  try {
    if (
      navigator.clipboard &&
      navigator.clipboard.writeText
    ) {
      await navigator
        .clipboard
        .writeText(text);

      return true;
    }
  } catch {
    // fallback abaixo
  }

  try {
    const textarea =
      document.createElement(
        "textarea"
      );

    textarea.value =
      text;

    textarea.style.position =
      "fixed";

    textarea.style.opacity =
      "0";

    document.body
      .appendChild(textarea);

    textarea.select();

    const success =
      document.execCommand(
        "copy"
      );

    textarea.remove();

    return success;

  } catch {
    return false;
  }
}

async function copyDiagnostic(item) {
  const text =
    buildDiagnosticText(item);

  const copied =
    await copyText(text);

  if (copied) {
    showToast(
      "Diagnóstico copiado."
    );
  } else {
    window.prompt(
      "Copie o diagnóstico:",
      text
    );
  }
}

async function copyAllDiagnostics() {
  if (
    state.diagnostics.length ===
    0
  ) {
    showToast(
      "Nenhum diagnóstico disponível."
    );

    return;
  }

  const header = [
    "################################",
    "CAFEÍNA - RELATÓRIO DE DIAGNÓSTICOS",
    `Total: ${state.diagnostics.length}`,
    `Gerado: ${formatDate(new Date())}`,
    "################################",
    ""
  ].join("\n");

  const body =
    state.diagnostics
      .map(buildDiagnosticText)
      .join(
        "\n\n"
        + "--------------------------------\n\n"
      );

  const text =
    header + body;

  const copied =
    await copyText(text);

  if (copied) {
    showToast(
      "Diagnósticos copiados."
    );
  } else {
    window.prompt(
      "Copie os diagnósticos:",
      text
    );
  }
}

// ============================================================
// RENDERIZAR DIAGNÓSTICOS
// ============================================================

function renderDiagnostics() {
  const list =
    $("diagnosticsList");

  if (!list) {
    return;
  }

  const filter =
    state.diagnosticFilter;

  const diagnostics =
    state.diagnostics
      .filter(item => {

        if (
          filter === "all"
        ) {
          return true;
        }

        return (
          String(
            item.type || ""
          )
            .toLowerCase() ===
          filter
        );
      });

  if (
    diagnostics.length === 0
  ) {
    list.innerHTML = "";

    const card =
      document.createElement("div");

    card.className =
      "state-card";

    const icon =
      document.createElement("div");

    icon.className =
      "state-icon";

    icon.textContent =
      state.diagnostics.length === 0
        ? "✓"
        : "⌕";

    const title =
      document.createElement("strong");

    title.textContent =
      state.diagnostics.length === 0
        ? "Nenhum erro recebido."
        : "Nenhum diagnóstico neste filtro.";

    const description =
      document.createElement("span");

    description.textContent =
      state.diagnostics.length === 0
        ? "Status: aguardando o Loader enviar um erro."
        : "Tente selecionar outro tipo de diagnóstico.";

    card.append(
      icon,
      title,
      description
    );

    list.appendChild(card);

    return;
  }

  list.innerHTML = "";

  diagnostics.forEach(item => {
    list.appendChild(
      createDiagnosticCard(item)
    );
  });
}

// ============================================================
// CARD DE DIAGNÓSTICO
// ============================================================

function createDiagnosticCard(item) {
  const card =
    document.createElement("article");

  card.className =
    "diagnostic-card";

  // CABEÇALHO

  const head =
    document.createElement("div");

  head.className =
    "diagnostic-head";

  const typeWrap =
    document.createElement("div");

  typeWrap.className =
    "diagnostic-type-wrap";

  const severity =
    document.createElement("span");

  severity.className =
    "diagnostic-severity";

  const type =
    document.createElement("span");

  type.className =
    "diagnostic-type";

  type.textContent =
    normalizeDiagnosticType(
      item.type
    );

  typeWrap.append(
    severity,
    type
  );

  const time =
    document.createElement("span");

  time.className =
    "diagnostic-time";

  time.textContent =
    formatDate(
      getDiagnosticDate(item)
    );

  head.append(
    typeWrap,
    time
  );

  // SCRIPT

  const scriptLine =
    document.createElement("div");

  scriptLine.className =
    "diagnostic-script";

  scriptLine.textContent =
    `Script: ${getScriptName(item)}`;

  // CORPO

  const body =
    document.createElement("div");

  body.className =
    "diagnostic-body";

  const message =
    document.createElement("div");

  message.className =
    "diagnostic-message";

  message.textContent =
    String(
      item.message ||
      "Sem mensagem."
    );

  // METADADOS

  const meta =
    document.createElement("div");

  meta.className =
    "diagnostic-meta";

  const metadata = [
    [
      "Versão",
      item.version
    ],

    [
      "PlaceId",
      item.placeId
    ],

    [
      "GameId",
      item.gameId
    ],

    [
      "Executor",
      item.executor
    ]
  ];

  metadata.forEach(
    ([label, value]) => {
      if (
        value === undefined ||
        value === null ||
        value === ""
      ) {
        return;
      }

      const pill =
        document.createElement("span");

      pill.className =
        "meta-pill";

      pill.textContent =
        `${label}: ${value}`;

      meta.appendChild(pill);
    }
  );

  body.append(
    scriptLine,
    message,
    meta
  );

  // TRACE

  if (item.trace) {
    const traceTitle =
      document.createElement("div");

    traceTitle.className =
      "trace-title";

    traceTitle.textContent =
      "TRACE";

    const trace =
      document.createElement("div");

    trace.className =
      "trace-box";

    trace.textContent =
      String(item.trace);

    body.append(
      traceTitle,
      trace
    );
  }

  // BOTÕES

  const actions =
    document.createElement("div");

  actions.className =
    "diagnostic-actions";

  const copyButton =
    document.createElement("button");

  copyButton.className =
    "file-action download";

  copyButton.textContent =
    "📋 Copiar este erro";

  copyButton.addEventListener(
    "click",
    () => {
      copyDiagnostic(item);
    }
  );

  actions.appendChild(
    copyButton
  );

  body.appendChild(
    actions
  );

  card.append(
    head,
    body
  );

  return card;
}

// ============================================================
// FILTROS
// ============================================================

function bindDiagnosticFilters() {
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

// ============================================================
// LIMPAR DIAGNÓSTICOS
// ============================================================

async function clearDiagnostics() {
  const confirmed =
    window.confirm(
      "Limpar todos os diagnósticos?"
    );

  if (!confirmed) {
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

    const data =
      await response
        .json()
        .catch(() => ({}));

    if (!response.ok) {
      throw new Error(
        data.message ||
        `HTTP ${response.status}`
      );
    }

    showToast(
      "Diagnósticos limpos."
    );

    await loadDiagnostics();

  } catch (error) {
    if (
      String(error.message)
        .toLowerCase()
        .includes("login") ||
      String(error.message)
        .toLowerCase()
        .includes("admin") ||
      String(error.message)
        .includes("401")
    ) {
      showToast(
        "É necessário login de administrador para limpar."
      );
    } else {
      showToast(
        `Erro: ${error.message}`
      );
    }
  }
}

// ============================================================
// ATUALIZAÇÃO AUTOMÁTICA
// ============================================================

function startDiagnosticPolling() {
  stopDiagnosticPolling();

  state.diagnosticTimer =
    window.setInterval(
      () => {
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
      },
      3000
    );
}

function stopDiagnosticPolling() {
  if (state.diagnosticTimer) {
    clearInterval(
      state.diagnosticTimer
    );

    state.diagnosticTimer =
      null;
  }
}

// ============================================================
// BOTÕES
// ============================================================

function bindButtons() {
  const refreshFiles =
    $("refreshFilesButton");

  if (refreshFiles) {
    refreshFiles.addEventListener(
      "click",
      loadFiles
    );
  }

  const refreshDiagnostics =
    $("refreshDiagnosticsButton");

  if (refreshDiagnostics) {
    refreshDiagnostics.addEventListener(
      "click",
      loadDiagnostics
    );
  }

  const clearDiagnosticsButton =
    $("clearDiagnosticsButton");

  if (clearDiagnosticsButton) {
    clearDiagnosticsButton.addEventListener(
      "click",
      clearDiagnostics
    );
  }

  const copyAllDiagnosticsButton =
    $("copyAllDiagnosticsButton");

  if (copyAllDiagnosticsButton) {
    copyAllDiagnosticsButton.addEventListener(
      "click",
      copyAllDiagnostics
    );
  }

  const refreshHealth =
    $("refreshHealthButton");

  if (refreshHealth) {
    refreshHealth.addEventListener(
      "click",
      checkHealth
    );
  }
}

// ============================================================
// INICIALIZAÇÃO
// ============================================================

async function bootstrap() {
  ensureDiagnosticsInterface();

  bindNavigation();
  bindDiagnosticFilters();
  bindButtons();

  await Promise.allSettled([
    checkHealth(),
    loadFiles(),
    loadDiagnostics()
  ]);
}

document.addEventListener(
  "DOMContentLoaded",
  bootstrap
);
