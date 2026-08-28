const state = {
  files: [],
  diagnostics: [],
  diagnosticFilter: "all",
  diagnosticTimer: null
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
    return;
  }

  toast.textContent =
    String(message || "");

  toast.classList.add("show");

  clearTimeout(
    window.__cafeinaToastTimer
  );

  window.__cafeinaToastTimer =
    setTimeout(() => {
      toast.classList.remove(
        "show"
      );
    }, 2400);
}

function formatBytes(bytes) {
  const number =
    Number(bytes || 0);

  if (
    !Number.isFinite(number) ||
    number <= 0
  ) {
    return "0 B";
  }

  const units = [
    "B",
    "KB",
    "MB",
    "GB",
    "TB"
  ];

  let value =
    number;

  let index =
    0;

  while (
    value >= 1024 &&
    index <
      units.length - 1
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

  return (
    `${value.toFixed(decimals)} ` +
    units[index]
  );
}

function formatDate(value) {
  if (!value) {
    return "Data desconhecida";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return "Data desconhecida";
  }

  return date
    .toLocaleString(
      "pt-BR"
    );
}

function formatShortTime(
  value
) {
  if (!value) {
    return "—";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime()
    )
  ) {
    return "—";
  }

  return date
    .toLocaleTimeString(
      "pt-BR",
      {
        hour:
          "2-digit",

        minute:
          "2-digit"
      }
    );
}

function setBadge(
  id,
  count
) {
  const badge =
    $(id);

  if (!badge) {
    return;
  }

  const number =
    Number(
      count || 0
    );

  badge.textContent =
    String(number);

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
  const el =
    $(id);

  if (!el) {
    return;
  }

  el.textContent =
    text;

  el.className =
    "status-value";

  if (stateName) {
    el.classList.add(
      stateName
    );
  }
}

// ============================================================
// NAVEGAÇÃO
// ============================================================

function openPage(
  pageName
) {
  document
    .querySelectorAll(
      ".page"
    )
    .forEach(page => {
      page.classList.remove(
        "active"
      );
    });

  const target =
    $(
      `page-${pageName}`
    );

  if (!target) {
    return;
  }

  target.classList.add(
    "active"
  );

  document
    .querySelectorAll(
      "[data-page]"
    )
    .forEach(button => {
      button.classList.toggle(
        "active",
        button.dataset.page ===
          pageName
      );
    });

  if (
    pageName ===
    "files"
  ) {
    loadFiles();
  }

  if (
    pageName ===
    "diagnostics"
  ) {
    loadDiagnostics();
    startDiagnosticPolling();
  } else {
    stopDiagnosticPolling();
  }

  if (
    pageName ===
    "status"
  ) {
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
          cache:
            "no-store"
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

    if (
      $("homeServerStatus")
    ) {
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
      data.downloads ===
        true;

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

    // Verifica separadamente
    // a API de diagnósticos.

    try {
      const diagnosticsResponse =
        await fetch(
          "/api/diagnostics",
          {
            cache:
              "no-store"
          }
        );

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

    if (
      $("homeServerStatus")
    ) {
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
          cache:
            "no-store"
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
      Array.isArray(
        data.files
      )
        ? data.files
        : [];

    state.files =
      files;

    const totalBytes =
      files.reduce(
        (
          sum,
          file
        ) => {
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

    if (
      $("homeFilesCount")
    ) {
      $("homeFilesCount")
        .textContent =
        String(
          files.length
        );
    }

    setBadge(
      "filesNavBadge",
      files.length
    );

    if (
      files.length === 0
    ) {
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

    list.innerHTML =
      "";

    files.forEach(
      file => {
        list.appendChild(
          createFileCard(
            file
          )
        );
      }
    );

  } catch (error) {
    console.error(
      "FILES ERROR:",
      error
    );

    count.textContent =
      "Erro";

    size.textContent =
      "Indisponível";

    list.innerHTML = "";

    const errorCard =
      document.createElement(
        "div"
      );

    errorCard.className =
      "state-card error-state";

    const icon =
      document.createElement(
        "div"
      );

    icon.className =
      "state-icon danger";

    icon.textContent =
      "!";

    const title =
      document.createElement(
        "strong"
      );

    title.textContent =
      "Não foi possível carregar os arquivos.";

    const description =
      document.createElement(
        "span"
      );

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

function createFileCard(
  file
) {
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

  const fileName =
    document.createElement(
      "div"
    );

  fileName.className =
    "file-name";

  fileName.textContent =
    name;

  const meta =
    document.createElement(
      "div"
    );

  meta.className =
    "file-meta";

  meta.textContent =
    `${formatBytes(bytes)} • ${formatDate(date)}`;

  main.append(
    fileName,
    meta
  );

  const actions =
    document.createElement(
      "div"
    );

  actions.className =
    "file-actions";

  // COPIAR LINK

  const copy =
    document.createElement(
      "button"
    );

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

  // DOWNLOAD

  const download =
    document.createElement(
      "button"
    );

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
// DIAGNÓSTICOS
// ============================================================

async function loadDiagnostics() {
  const list =
    $("diagnosticsList");

  const count =
    $("diagnosticsCount");

  const lastType =
    $("diagnosticsLastType");

  const updatedAt =
    $("diagnosticsUpdatedAt");

  if (
    !list ||
    !count ||
    !lastType
  ) {
    return;
  }

  try {
    const response =
      await fetch(
        "/api/diagnostics",
        {
          cache:
            "no-store"
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

    const diagnostics =
      Array.isArray(
        data.diagnostics
      )
        ? data.diagnostics
        : [];

    state.diagnostics =
      diagnostics;

    count.textContent =
      diagnostics.length === 1
        ? "1 registro"
        : `${diagnostics.length} registros`;

    lastType.textContent =
      diagnostics[0]?.type
        ? normalizeDiagnosticType(
            diagnostics[0]
              .type
          )
        : "Nenhum";

    if (updatedAt) {
      updatedAt.textContent =
        formatShortTime(
          new Date()
        );
    }

    if (
      $("homeDiagnosticsCount")
    ) {
      $("homeDiagnosticsCount")
        .textContent =
        String(
          diagnostics.length
        );
    }

    setBadge(
      "diagnosticsNavBadge",
      diagnostics.length
    );

    renderDiagnostics();

  } catch (error) {
    console.error(
      "DIAGNOSTICS ERROR:",
      error
    );

    count.textContent =
      "Erro";

    lastType.textContent =
      "Indisponível";

    list.innerHTML =
      "";

    const errorCard =
      document.createElement(
        "div"
      );

    errorCard.className =
      "state-card error-state";

    const icon =
      document.createElement(
        "div"
      );

    icon.className =
      "state-icon danger";

    icon.textContent =
      "!";

    const title =
      document.createElement(
        "strong"
      );

    title.textContent =
      "Não foi possível carregar os diagnósticos.";

    const description =
      document.createElement(
        "span"
      );

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

function normalizeDiagnosticType(
  type
) {
  const key =
    String(
      type || ""
    )
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
          filter ===
          "all"
        ) {
          return true;
        }

        return (
          String(
            item.type ||
            ""
          )
            .toLowerCase() ===
          filter
        );
      });

  if (
    diagnostics.length ===
    0
  ) {
    list.innerHTML = `
      <div class="state-card">
        <div class="state-icon danger">
          !
        </div>

        <strong>
          Nenhum diagnóstico neste filtro.
        </strong>

        <span>
          Quando o Loader enviar um erro, ele aparecerá aqui.
        </span>
      </div>
    `;

    return;
  }

  list.innerHTML =
    "";

  diagnostics.forEach(
    item => {
      list.appendChild(
        createDiagnosticCard(
          item
        )
      );
    }
  );
}

// ============================================================
// CARD DE DIAGNÓSTICO
// ============================================================

function createDiagnosticCard(
  item
) {
  const card =
    document.createElement(
      "article"
    );

  card.className =
    "diagnostic-card";

  // CABEÇALHO

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

  const severity =
    document.createElement(
      "span"
    );

  severity.className =
    "diagnostic-severity";

  const type =
    document.createElement(
      "span"
    );

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
    document.createElement(
      "span"
    );

  time.className =
    "diagnostic-time";

  time.textContent =
    formatDate(
      item.receivedAt ||
      item.clientTime
    );

  head.append(
    typeWrap,
    time
  );

  // CORPO

  const body =
    document.createElement(
      "div"
    );

  body.className =
    "diagnostic-body";

  const message =
    document.createElement(
      "div"
    );

  message.className =
    "diagnostic-message";

  message.textContent =
    String(
      item.message ||
      "Sem mensagem."
    );

  // METADADOS

  const meta =
    document.createElement(
      "div"
    );

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

      if (!value) {
        return;
      }

      const pill =
        document.createElement(
          "span"
        );

      pill.className =
        "meta-pill";

      pill.textContent =
        `${label}: ${value}`;

      meta.appendChild(
        pill
      );
    }
  );

  body.append(
    message,
    meta
  );

  // TRACEBACK

  if (item.trace) {
    const trace =
      document.createElement(
        "div"
      );

    trace.className =
      "trace-box";

    trace.textContent =
      String(
        item.trace
      );

    body.appendChild(
      trace
    );
  }

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
          method:
            "DELETE",

          credentials:
            "same-origin"
        }
      );

    const data =
      await response
        .json()
        .catch(
          () => ({})
        );

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
      error.message ===
      "Faça login."
    ) {
      showToast(
        "Faça login como administrador para limpar."
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
          $(
            "page-diagnostics"
          );

        if (
          page &&
          page.classList
            .contains(
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

// ============================================================
// BOTÕES
// ============================================================

function bindButtons() {
  const refreshFiles =
    $(
      "refreshFilesButton"
    );

  if (refreshFiles) {
    refreshFiles
      .addEventListener(
        "click",
        loadFiles
      );
  }

  const refreshDiagnostics =
    $(
      "refreshDiagnosticsButton"
    );

  if (
    refreshDiagnostics
  ) {
    refreshDiagnostics
      .addEventListener(
        "click",
        loadDiagnostics
      );
  }

  const clearDiagnosticsButton =
    $(
      "clearDiagnosticsButton"
    );

  if (
    clearDiagnosticsButton
  ) {
    clearDiagnosticsButton
      .addEventListener(
        "click",
        clearDiagnostics
      );
  }

  const refreshHealth =
    $(
      "refreshHealthButton"
    );

  if (refreshHealth) {
    refreshHealth
      .addEventListener(
        "click",
        checkHealth
      );
  }
}

// ============================================================
// INICIALIZAÇÃO
// ============================================================

async function bootstrap() {
  bindNavigation();

  bindButtons();

  bindDiagnosticFilters();

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
