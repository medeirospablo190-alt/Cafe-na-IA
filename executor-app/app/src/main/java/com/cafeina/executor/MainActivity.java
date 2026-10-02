package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.cafeina.runtime.LuauBridge;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int PANEL = Color.rgb(24, 25, 33);
    private static final int PANEL_2 = Color.rgb(38, 41, 49);
    private static final int ACCENT = Color.rgb(59, 139, 254);
    private static final int TEXT = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(165, 170, 182);
    private static final int REQUEST_EXPORT_ARCHIVE = 9101;
    private static final int REQUEST_IMPORT_ARCHIVE = 9102;
    private static final int REQUEST_IMPORT_LOCAL_MODEL = 9103;
    private static final String LOCAL_MODEL_PREFS = "cafeina_ai_local_model";
    private static final String ACTIVE_LOCAL_MODEL = "active_model_filename";
    private static final String ZIP_MIME = "application/zip";
    private static final String DEFAULT_SOURCE = "print(\"Olá do CAFEÍNA\")\nreturn 6 * 7";

    private final ExecutorService runtimeExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();
    private final EditorTabs tabs = new EditorTabs(DEFAULT_SOURCE);
    private final EditorUndoHistory editorHistory = new EditorUndoHistory();

    private ScriptStore scriptStore;
    private AutoExecuteStore autoExecuteStore;
    private String runtimeFilesRoot;
    private ProjectWorkspace workspace;
    private int editorFontSp = 17;
    private EditText editor;
    private TextView console;
    private TextView status;
    private Button executeButton;
    private Button clearButton;
    private Button saveButton;
    private Button loadButton;
    private Button autoExecuteButton;
    private Button addTabButton;
    private Button undoButton;
    private Button redoButton;
    private LinearLayout tabButtons;
    private HorizontalScrollView tabScroll;
    private boolean suppressEditorWatcher;
    private boolean autoExecStartupTriggered;
    private LinearLayout screenHost;
    private LinearLayout codeScreen;
    private LaboratoryAiChatPanel aiChatPanel;
    private Button localModelImportButton;
    private Button localModelSelectButton;
    private Button localModelTestButton;
    private TextView localModelStatus;
    private volatile boolean localModelImportInProgress;
    private volatile boolean localModelRuntimeInProgress;
    private String localModelMessage =
        "Nenhum modelo é carregado automaticamente.";
    private final Map<String, Button> navigation = new LinkedHashMap<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String requestedProject = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        String workspaceWarning = null;
        try {
            workspace = ProjectWorkspace.open(getFilesDir(), requestedProject);
        } catch (Exception error) {
            workspaceWarning = "O projeto selecionado não está disponível: " + error.getMessage()
                + ". Seus arquivos não foram apagados. Usando os scripts antigos.";
            getSharedPreferences("cafeina_workspace", MODE_PRIVATE).edit()
                .remove("project_id").apply();
            workspace = ProjectWorkspace.openLegacy(getFilesDir());
        }
        scriptStore = workspace.scriptStore();
        autoExecuteStore = workspace.autoExecuteStore();
        runtimeFilesRoot = workspace.runtimeFilesRoot();
        editorFontSp = getSharedPreferences("cafeina_ui", MODE_PRIVATE)
            .getInt("editor_font_sp", 17);
        editorFontSp = Math.max(14, Math.min(26, editorFontSp));
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        setContentView(buildAppUi());
        if (workspaceWarning != null) {
            new AlertDialog.Builder(this)
                .setTitle("Projeto indisponível")
                .setMessage(workspaceWarning)
                .setPositiveButton("OK", null)
                .show();
        }
        restoreSavedTabs();
        scanInterruptedAiSessions();
    }


    private void scanInterruptedAiSessions() {
        final String projectId = workspace.id();
        ioExecutor.submit(() -> {
            try {
                LaboratoryAiSessionRecovery recovery =
                    new LaboratoryAiSessionRecovery(getFilesDir(), projectId);
                List<LaboratoryAiSessionRecovery.Item> pending =
                    recovery.markInterruptedOrphans();
                if (pending.isEmpty()) return;
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    new AlertDialog.Builder(this)
                        .setTitle("Sessão da IA interrompida")
                        .setMessage(pending.size()
                            + " sessão(ões) aguardam uma decisão. "
                            + "Nada será retomado automaticamente.")
                        .setNegativeButton("DEPOIS", null)
                        .setPositiveButton("REVISAR", (dialog, which) ->
                            startActivity(new Intent(
                                this, LaboratoryAiSessionRecoveryActivity.class)))
                        .show();
                });
            } catch (Exception ignored) {
                // Recovery problems remain visible in SISTEMA > relatórios.
                // Startup of the editor must not be blocked by a damaged audit.
            }
        });
    }


    // Product shell: the editor stays alive when moving between sections.
    private LinearLayout buildAppUi() {
        LinearLayout app = new LinearLayout(this);
        app.setOrientation(LinearLayout.VERTICAL);
        app.setBackgroundColor(BG);

        TextView brand = new TextView(this);
        brand.setText((getPackageName().endsWith(".preview") ? "CAFEÍNA TESTE" : "CAFEÍNA")
            + " • " + workspace.label());
        brand.setTextColor(TEXT);
        brand.setTextSize(21);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setPadding(dp(16), dp(13), dp(16), dp(8));
        app.addView(brand, matchWrap());

        HorizontalScrollView navigationScroll = new HorizontalScrollView(this);
        navigationScroll.setHorizontalScrollBarEnabled(false);
        LinearLayout navigationBar = new LinearLayout(this);
        navigationBar.setPadding(dp(10), 0, dp(10), dp(6));
        navigationBar.setOrientation(LinearLayout.HORIZONTAL);
        navigationScroll.addView(navigationBar);

        for (String name : new String[]{"IA", "CÓDIGO", "MUNDO", "3D", "SISTEMA"}) {
            Button section = makeButton(name, name.equals("CÓDIGO") ? ACCENT : PANEL_2);
            section.setAllCaps(false);
            section.setTextSize(13);
            section.setMinWidth(dp(82));
            LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(46));
            params.setMargins(dp(3), 0, dp(3), 0);
            navigationBar.addView(section, params);
            navigation.put(name, section);
            section.setOnClickListener(v -> showSection(name));
        }

        app.addView(navigationScroll, matchWrap());
        screenHost = new LinearLayout(this);
        screenHost.setOrientation(LinearLayout.VERTICAL);
        app.addView(screenHost,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        codeScreen = buildUi();
        screenHost.addView(codeScreen,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        return app;
    }

    private void showSection(String name) {
        if ("MUNDO".equals(name)) {
            openWorld();
            return;
        }
        if ("SISTEMA".equals(name)) {
            openProjectManager();
            return;
        }
        for (Map.Entry<String, Button> item : navigation.entrySet()) {
            item.getValue().setBackgroundTintList(ColorStateList.valueOf(
                item.getKey().equals(name) ? ACCENT : PANEL_2
            ));
        }
        screenHost.removeAllViews();
        if ("CÓDIGO".equals(name)) {
            screenHost.addView(codeScreen,
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));
            return;
        }

        LinearLayout section = new LinearLayout(this);
        section.setOrientation(LinearLayout.VERTICAL);
        section.setPadding(dp(20), dp(30), dp(20), dp(20));
        TextView title = new TextView(this);
        title.setText(name);
        title.setTextSize(22);
        title.setTextColor(TEXT);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        section.addView(title, matchWrap());

        TextView detail = new TextView(this);
        detail.setTextSize(16);
        detail.setTextColor(MUTED);
        detail.setPadding(0, dp(15), 0, dp(22));
        if ("3D".equals(name)) {
            detail.setText("O módulo de criação e edição 3D ainda está em desenvolvimento. Nenhuma alteração será feita nos seus scripts ao entrar nesta área.");
        } else if ("IA".equals(name)) {
            detail.setText(
                "Converse com a CAFEÍNA normalmente. Mensagens comuns usam o "
                    + "modelo local sem ferramentas; pedidos de ação entram no "
                    + "Goal Lock e nas permissões antes de qualquer execução.");
        } else {
            detail.setText("A execução Luau, o editor e o armazenamento privado já estão disponíveis na aba CÓDIGO.");
        }
        section.addView(detail, matchWrap());

        if ("IA".equals(name)) {
            if (aiChatPanel == null) {
                aiChatPanel = new LaboratoryAiChatPanel(
                    this, workspace.id());
            }
            section.addView(
                aiChatPanel,
                new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    0,
                    1f));

            TextView modelConfigTitle = new TextView(this);
            modelConfigTitle.setText("MODELO LOCAL • CONFIGURAÇÃO");
            modelConfigTitle.setTextColor(TEXT);
            modelConfigTitle.setTextSize(13);
            modelConfigTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            LinearLayout.LayoutParams configTitleParams = matchWrap();
            configTitleParams.setMargins(0, dp(10), 0, dp(4));
            section.addView(modelConfigTitle, configTitleParams);

            localModelStatus = new TextView(this);
            localModelStatus.setText(localModelImportInProgress
                ? "Importando modelo para o armazenamento privado…"
                : localModelMessage);
            localModelStatus.setTextColor(MUTED);
            localModelStatus.setTextSize(13);
            LinearLayout.LayoutParams modelStatusParams = matchWrap();
            modelStatusParams.setMargins(0, 0, 0, dp(10));
            section.addView(localModelStatus, modelStatusParams);

            localModelImportButton = makeButton(
                localModelImportInProgress
                    ? "IMPORTANDO MODELO…"
                    : "IMPORTAR MODELO GGUF",
                PANEL_2);
            localModelImportButton.setEnabled(!localModelImportInProgress);
            localModelImportButton.setOnClickListener(
                v -> requestImportLocalModel());
            LinearLayout.LayoutParams modelButtonParams = matchWrap();
            modelButtonParams.setMargins(0, 0, 0, dp(10));
            section.addView(localModelImportButton, modelButtonParams);

            localModelSelectButton = makeButton(
                "SELECIONAR MODELO ATIVO",
                PANEL_2);
            localModelSelectButton.setEnabled(
                !localModelImportInProgress && !localModelRuntimeInProgress);
            localModelSelectButton.setOnClickListener(
                v -> requestSelectLocalModel());
            LinearLayout.LayoutParams selectModelParams = matchWrap();
            selectModelParams.setMargins(0, 0, 0, dp(10));
            section.addView(localModelSelectButton, selectModelParams);

            localModelTestButton = makeButton(
                localModelRuntimeInProgress
                    ? "TESTANDO MODELO…"
                    : "TESTAR MODELO LOCAL",
                ACCENT);
            localModelTestButton.setEnabled(
                !localModelImportInProgress
                    && !localModelRuntimeInProgress
                    && !selectedLocalModelFileName().isEmpty());
            localModelTestButton.setOnClickListener(
                v -> testSelectedLocalModel());
            LinearLayout.LayoutParams testModelParams = matchWrap();
            testModelParams.setMargins(0, 0, 0, dp(10));
            section.addView(localModelTestButton, testModelParams);

            Button localPlannerButton = makeButton(
                "TESTAR PLANEJADOR LOCAL",
                PANEL_2);
            localPlannerButton.setEnabled(
                !localModelImportInProgress
                    && !localModelRuntimeInProgress
                    && !selectedLocalModelFileName().isEmpty());
            localPlannerButton.setOnClickListener(v ->
                startActivity(new Intent(
                    this, LaboratoryAiLocalPlannerActivity.class)));
            LinearLayout.LayoutParams plannerParams = matchWrap();
            plannerParams.setMargins(0, 0, 0, dp(10));
            section.addView(localPlannerButton, plannerParams);
        }

        Button back = makeButton("VOLTAR AO CÓDIGO", ACCENT);
        back.setOnClickListener(v -> showSection("CÓDIGO"));
        section.addView(back, matchWrap());
        screenHost.addView(section,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
    }



    private void openWorld() {
        if (!editor.isEnabled() || !executeButton.isEnabled() || !saveButton.isEnabled()
                || !loadButton.isEnabled()) {
            status.setText("Aguarde a operação atual antes de abrir o mundo.");
            return;
        }
        if (hasUnsavedTabs()) {
            new AlertDialog.Builder(this)
                .setTitle("Salve o código antes de abrir o mundo")
                .setMessage("Salve as abas alteradas. O mundo abre dentro deste aplicativo e seus scripts não serão modificados.")
                .setPositiveButton("VOLTAR E SALVAR", null)
                .show();
            return;
        }
        startActivity(new Intent(this, GodotWorldActivity.class));
    }

    private void openProjectManager() {
        if (!editor.isEnabled() || !executeButton.isEnabled() || !saveButton.isEnabled()
                || !loadButton.isEnabled()) {
            new AlertDialog.Builder(this)
                .setTitle("Operação em andamento")
                .setMessage("Aguarde a execução ou a gravação terminar antes de trocar de projeto.")
                .setPositiveButton("OK", null)
                .show();
            return;
        }
        tabs.updateActiveContent(editor.getText().toString());
        boolean hasUnsaved = false;
        for (int i = 0; i < tabs.size(); i++) {
            if (tabs.isDirtyAt(i)) {
                hasUnsaved = true;
                break;
            }
        }
        if (hasUnsaved) {
            new AlertDialog.Builder(this)
                .setTitle("Alterações não salvas")
                .setMessage("Salve todas as abas alteradas antes de trocar de projeto. "
                    + "A troca não descarta rascunhos.")
                .setPositiveButton("VOLTAR E SALVAR", null)
                .show();
            return;
        }
        startActivity(new Intent(this, ProjectManagerActivity.class));
    }

    private void changeEditorFont(int difference) {
        editorFontSp = Math.max(14, Math.min(26, editorFontSp + difference));
        editor.setTextSize(editorFontSp);
        getSharedPreferences("cafeina_ui", MODE_PRIVATE).edit()
            .putInt("editor_font_sp", editorFontSp).apply();
    }

    private LinearLayout buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(14), dp(14), dp(14), dp(14));
        root.setBackgroundColor(BG);

        TextView title = new TextView(this);
        title.setText("CÓDIGO • LUAU");
        title.setTextColor(TEXT);
        title.setTextSize(17);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Projeto: " + workspace.label() + " • VM Luau isolada");
        subtitle.setTextColor(MUTED);
        subtitle.setTextSize(11);
        LinearLayout.LayoutParams subtitleParams = matchWrap();
        subtitleParams.setMargins(0, dp(2), 0, dp(8));
        root.addView(subtitle, subtitleParams);

        tabScroll = new HorizontalScrollView(this);
        tabScroll.setHorizontalScrollBarEnabled(false);
        tabScroll.setFillViewport(false);

        tabButtons = new LinearLayout(this);
        tabButtons.setOrientation(LinearLayout.HORIZONTAL);
        tabScroll.addView(tabButtons, new HorizontalScrollView.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(42)
        ));

        LinearLayout.LayoutParams tabScrollParams =
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(42));
        tabScrollParams.setMargins(0, 0, 0, dp(8));
        root.addView(tabScroll, tabScrollParams);

        LinearLayout fontControls = new LinearLayout(this);
        fontControls.setOrientation(LinearLayout.HORIZONTAL);
        TextView fontLabel = new TextView(this);
        fontLabel.setText("TAMANHO DO CÓDIGO");
        fontLabel.setTextColor(MUTED);
        fontLabel.setTextSize(13);
        fontControls.addView(fontLabel, new LinearLayout.LayoutParams(0, dp(48), 1f));
        fontLabel.setGravity(Gravity.CENTER_VERTICAL);
        Button fontDown = makeButton("A−", PANEL_2);
        Button fontUp = makeButton("A+", PANEL_2);
        fontDown.setOnClickListener(v -> changeEditorFont(-1));
        fontUp.setOnClickListener(v -> changeEditorFont(1));
        fontControls.addView(fontDown, new LinearLayout.LayoutParams(dp(64), dp(48)));
        LinearLayout.LayoutParams fontUpParams = new LinearLayout.LayoutParams(dp(64), dp(48));
        fontUpParams.setMargins(dp(6), 0, 0, 0);
        fontControls.addView(fontUp, fontUpParams);
        root.addView(fontControls, matchWrap());

        LinearLayout historyControls = new LinearLayout(this);
        historyControls.setOrientation(LinearLayout.HORIZONTAL);
        undoButton = makeButton("DESFAZER", PANEL_2);
        redoButton = makeButton("REFAZER", PANEL_2);
        undoButton.setContentDescription("Desfazer alteração no código");
        redoButton.setContentDescription("Refazer alteração no código");
        addTwoButtons(historyControls, undoButton, redoButton);
        LinearLayout.LayoutParams historyParams = matchWrap();
        historyParams.setMargins(0, 0, 0, dp(6));
        root.addView(historyControls, historyParams);
        undoButton.setOnClickListener(v -> restoreEditorHistory(false));
        redoButton.setOnClickListener(v -> restoreEditorHistory(true));
        undoButton.setEnabled(false);
        redoButton.setEnabled(false);

        editor = new LuauCodeEditor(this);
        editor.setText(tabs.activeContent());
        editor.setTextColor(TEXT);
        editor.setHintTextColor(MUTED);
        editor.setBackgroundColor(PANEL);
        editor.setTypeface(Typeface.MONOSPACE);
        editor.setTextSize(editorFontSp);
        editor.setGravity(Gravity.TOP | Gravity.START);
        // LuauCodeEditor reserves its own gutter and responsive padding.
        editor.setInputType(
            InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        );
        editor.setHorizontallyScrolling(false);
        editor.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
            }

            @Override
            public void afterTextChanged(Editable value) {
                if (suppressEditorWatcher) return;

                boolean wasDirty = tabs.activeDirty();
                editorHistory.record(tabs.activeName(), tabs.activeContent(), value.toString());
                tabs.updateActiveContent(value.toString());
                refreshHistoryButtons();
                boolean nowDirty = tabs.activeDirty();

                if (wasDirty != nowDirty) {
                    renderTabs();
                    refreshAutoExecButton();
                }

                if (nowDirty) {
                    status.setText("Alterado • " + tabs.activeName());
                }
            }
        });

        LinearLayout.LayoutParams editorParams =
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        editorParams.setMargins(0, 0, 0, dp(10));
        root.addView(editor, editorParams);

        LinearLayout primaryActions = new LinearLayout(this);
        primaryActions.setOrientation(LinearLayout.HORIZONTAL);

        executeButton = makeButton("EXECUTE", ACCENT);
        clearButton = makeButton("CLEAR", Color.rgb(61, 66, 81));
        addTwoButtons(primaryActions, executeButton, clearButton);
        root.addView(primaryActions, matchWrap());

        LinearLayout storageActions = new LinearLayout(this);
        storageActions.setOrientation(LinearLayout.HORIZONTAL);

        saveButton = makeButton("SAVE", Color.rgb(48, 121, 89));
        loadButton = makeButton("LOAD", Color.rgb(78, 82, 101));
        addTwoButtons(storageActions, saveButton, loadButton);

        LinearLayout.LayoutParams storageParams = matchWrap();
        storageParams.setMargins(0, dp(6), 0, 0);
        root.addView(storageActions, storageParams);

        LinearLayout archiveActions = new LinearLayout(this);
        archiveActions.setOrientation(LinearLayout.HORIZONTAL);
        Button exportArchive = makeButton("EXPORTAR ZIP", Color.rgb(52, 100, 121));
        Button importArchive = makeButton("IMPORTAR ZIP", Color.rgb(92, 76, 119));
        addTwoButtons(archiveActions, exportArchive, importArchive);
        LinearLayout.LayoutParams archiveParams = matchWrap();
        archiveParams.setMargins(0, dp(6), 0, 0);
        root.addView(archiveActions, archiveParams);
        exportArchive.setOnClickListener(v -> requestExportArchive());
        importArchive.setOnClickListener(v -> requestImportArchive());

        autoExecuteButton = makeButton("AUTOEXEC: CHECKING", Color.rgb(89, 74, 120));
        autoExecuteButton.setEnabled(false);
        LinearLayout.LayoutParams autoExecParams = matchWrap();
        autoExecParams.setMargins(0, dp(6), 0, 0);
        root.addView(autoExecuteButton, autoExecParams);

        status = new TextView(this);
        status.setText("Preparando...");
        status.setTextColor(MUTED);
        status.setTextSize(13);
        LinearLayout.LayoutParams statusParams = matchWrap();
        statusParams.setMargins(0, dp(8), 0, dp(6));
        root.addView(status, statusParams);

        ScrollView consoleScroll = new ScrollView(this);
        consoleScroll.setFillViewport(true);
        consoleScroll.setBackgroundColor(PANEL_2);

        console = new TextView(this);
        console.setText("Console aguardando execução.");
        console.setTextColor(TEXT);
        console.setTextSize(14);
        console.setTypeface(Typeface.MONOSPACE);
        console.setPadding(dp(12), dp(10), dp(12), dp(10));
        console.setTextIsSelectable(true);
        consoleScroll.addView(console, new ScrollView.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ));

        LinearLayout.LayoutParams consoleParams =
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(150));
        root.addView(consoleScroll, consoleParams);

        executeButton.setOnClickListener(v -> executeSource());
        clearButton.setOnClickListener(v -> clearActiveTab());
        saveButton.setOnClickListener(v -> saveActiveScript());
        loadButton.setOnClickListener(v -> showLoadPicker());
        autoExecuteButton.setOnClickListener(v -> toggleAutoExecute());

        installKeyboardLayout(root, primaryActions, storageActions, archiveActions, consoleScroll);
        renderTabs();
        return root;
    }


    /**
     * The editor occupies the remaining screen height. When the IME appears,
     * fixed action rows and the console would otherwise leave no room for code.
     * Keep tabs/font/history visible and restore the other controls on dismissal.
     */
    private void installKeyboardLayout(LinearLayout root, View primaryActions,
            View storageActions, View archiveActions, View consoleScroll) {
        final int[] fullHeight = {0};
        final boolean[] compact = {false};
        final Rect visible = new Rect();
        root.getViewTreeObserver().addOnGlobalLayoutListener(() -> {
            if (!root.isAttachedToWindow() || root.getHeight() <= 0) return;
            WindowInsets insets = root.getRootWindowInsets();
            boolean imeVisible = Build.VERSION.SDK_INT >= 30 && insets != null
                && insets.isVisible(WindowInsets.Type.ime());

            // Older Android versions: track the expanded layout and visible frame.
            root.getWindowVisibleDisplayFrame(visible);
            int covered = Math.max(0, root.getRootView().getHeight() - visible.bottom);
            if (!imeVisible && covered < dp(160)) {
                fullHeight[0] = Math.max(fullHeight[0], root.getHeight());
            }
            boolean shouldCompact = imeVisible || covered > dp(160)
                || (fullHeight[0] > 0 && fullHeight[0] - root.getHeight() > dp(120));
            if (shouldCompact == compact[0]) return;
            compact[0] = shouldCompact;
            int visibility = shouldCompact ? View.GONE : View.VISIBLE;
            primaryActions.setVisibility(visibility);
            storageActions.setVisibility(visibility);
            archiveActions.setVisibility(visibility);
            autoExecuteButton.setVisibility(visibility);
            consoleScroll.setVisibility(visibility);
            status.setVisibility(visibility);
        });
    }

    private boolean hasUnsavedTabs() {
        tabs.updateActiveContent(editor.getText().toString());
        for (int i = 0; i < tabs.size(); i++) {
            if (tabs.isDirtyAt(i)) return true;
        }
        return false;
    }

    private boolean requireSavedForArchive() {
        if (!editor.isEnabled() || !executeButton.isEnabled() || !saveButton.isEnabled()
                || !loadButton.isEnabled()) {
            status.setText("Aguarde a operação atual antes de usar o backup.");
            return false;
        }
        if (!hasUnsavedTabs()) return true;
        new AlertDialog.Builder(this)
            .setTitle("Salve antes do backup")
            .setMessage("Salve as abas alteradas para garantir que o ZIP contenha a versão correta "
                + "e que a importação não substitua nenhum rascunho.")
            .setPositiveButton("VOLTAR E SALVAR", null)
            .show();
        return false;
    }

    private void requestExportArchive() {
        if (!requireSavedForArchive()) return;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(ZIP_MIME);
        String prefix = workspace.id().isEmpty() ? "scripts-antigos" : workspace.id();
        intent.putExtra(Intent.EXTRA_TITLE, "cafeina-" + prefix + "-scripts.zip");
        startActivityForResult(intent, REQUEST_EXPORT_ARCHIVE);
    }

    private void requestImportArchive() {
        if (!requireSavedForArchive()) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(ZIP_MIME);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_IMPORT_ARCHIVE);
    }

    private void requestImportLocalModel() {
        if (localModelImportInProgress || localModelRuntimeInProgress) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivityForResult(intent, REQUEST_IMPORT_LOCAL_MODEL);
    }

    private void importLocalModel(Uri document) {
        if (document == null || localModelImportInProgress) return;

        localModelImportInProgress = true;
        localModelMessage =
            "Importando modelo para o armazenamento privado…";
        if (localModelStatus != null) {
            localModelStatus.setText(localModelMessage);
        }
        if (localModelImportButton != null) {
            localModelImportButton.setText("IMPORTANDO MODELO…");
            localModelImportButton.setEnabled(false);
        }
        setControlsEnabled(false);
        status.setText("Importando modelo local…");

        ioExecutor.submit(() -> {
            try {
                final LaboratoryAiLocalModelStore.ImportResult imported;
                try (InputStream input =
                        getContentResolver().openInputStream(document)) {
                    if (input == null) {
                        throw new java.io.IOException(
                            "Não foi possível abrir o arquivo escolhido.");
                    }
                    imported = LaboratoryAiLocalModelStore.importGguf(
                        getFilesDir(), input);
                }

                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    localModelImportInProgress = false;
                    localModelMessage =
                        (imported.duplicate
                            ? "Modelo já estava importado"
                            : "Modelo importado")
                        + " • " + modelSizeLabel(imported.sizeBytes)
                        + " • " + imported.sha256.substring(0, 12);
                    if (localModelStatus != null) {
                        localModelStatus.setText(localModelMessage);
                    }
                    if (localModelImportButton != null) {
                        localModelImportButton.setText("IMPORTAR MODELO GGUF");
                    }
                    refreshLocalModelButtons();
                    setControlsEnabled(true);
                    status.setText(localModelMessage);
                    refreshAutoExecButton();

                    new AlertDialog.Builder(this)
                        .setTitle(imported.duplicate
                            ? "Modelo já importado"
                            : "Modelo importado")
                        .setMessage(
                            "O GGUF foi copiado para o armazenamento privado do "
                                + "CAFEÍNA e ainda não foi carregado ou executado."
                                + "\n\nSHA-256: " + imported.sha256
                                + "\nTamanho: "
                                + modelSizeLabel(imported.sizeBytes))
                        .setPositiveButton("OK", null)
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    localModelImportInProgress = false;
                    localModelMessage =
                        "Falha ao importar o modelo: "
                            + String.valueOf(error.getMessage());
                    if (localModelStatus != null) {
                        localModelStatus.setText(localModelMessage);
                    }
                    if (localModelImportButton != null) {
                        localModelImportButton.setText("IMPORTAR MODELO GGUF");
                    }
                    refreshLocalModelButtons();
                    setControlsEnabled(true);
                    status.setText("Falha ao importar modelo local");
                    refreshAutoExecButton();
                    new AlertDialog.Builder(this)
                        .setTitle("Modelo não importado")
                        .setMessage(
                            "O arquivo não foi publicado como modelo local. "
                                + String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
                        .show();
                });
            }
        });
    }

    private String selectedLocalModelFileName() {
        return getSharedPreferences(LOCAL_MODEL_PREFS, MODE_PRIVATE)
            .getString(ACTIVE_LOCAL_MODEL, "");
    }

    private void requestSelectLocalModel() {
        if (localModelImportInProgress || localModelRuntimeInProgress) return;

        localModelMessage = "Lendo modelos importados…";
        if (localModelStatus != null) {
            localModelStatus.setText(localModelMessage);
        }
        refreshLocalModelButtons();

        ioExecutor.submit(() -> {
            try {
                final List<LaboratoryAiLocalModelCatalog.Model> models =
                    LaboratoryAiLocalModelCatalog.list(getFilesDir());
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    if (models.isEmpty()) {
                        localModelMessage =
                            "Nenhum GGUF importado. Importe um modelo primeiro.";
                        if (localModelStatus != null) {
                            localModelStatus.setText(localModelMessage);
                        }
                        refreshLocalModelButtons();
                        return;
                    }

                    String[] labels = new String[models.size()];
                    String current = selectedLocalModelFileName();
                    int checked = -1;
                    for (int i = 0; i < models.size(); i++) {
                        LaboratoryAiLocalModelCatalog.Model model =
                            models.get(i);
                        labels[i] =
                            model.fileName.substring(
                                0, Math.min(12, model.fileName.length()))
                            + " • " + modelSizeLabel(model.sizeBytes);
                        if (model.fileName.equals(current)) {
                            checked = i;
                        }
                    }

                    AlertDialog.Builder picker =
                        new AlertDialog.Builder(this)
                            .setTitle("Selecionar modelo local")
                            .setSingleChoiceItems(
                                labels,
                                checked,
                                (dialog, which) -> {
                                    LaboratoryAiLocalModelCatalog.Model chosen =
                                        models.get(which);
                                    getSharedPreferences(
                                            LOCAL_MODEL_PREFS,
                                            MODE_PRIVATE)
                                        .edit()
                                        .putString(
                                            ACTIVE_LOCAL_MODEL,
                                            chosen.fileName)
                                        .apply();
                                    localModelMessage =
                                        "Modelo ativo • "
                                            + chosen.fileName.substring(
                                                0,
                                                Math.min(
                                                    12,
                                                    chosen.fileName.length()))
                                            + " • "
                                            + modelSizeLabel(
                                                chosen.sizeBytes);
                                    if (localModelStatus != null) {
                                        localModelStatus.setText(
                                            localModelMessage);
                                    }
                                    refreshLocalModelButtons();
                                    dialog.dismiss();
                                })
                            .setNegativeButton("Cancelar", null);
                    picker.show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    localModelMessage =
                        "Falha ao listar modelos: "
                            + String.valueOf(error.getMessage());
                    if (localModelStatus != null) {
                        localModelStatus.setText(localModelMessage);
                    }
                    refreshLocalModelButtons();
                });
            }
        });
    }

    private void testSelectedLocalModel() {
        if (localModelImportInProgress || localModelRuntimeInProgress) return;

        final String selected = selectedLocalModelFileName();
        if (selected.isEmpty()) {
            localModelMessage = "Selecione um modelo ativo primeiro.";
            if (localModelStatus != null) {
                localModelStatus.setText(localModelMessage);
            }
            refreshLocalModelButtons();
            return;
        }

        localModelRuntimeInProgress = true;
        localModelMessage =
            "Executando preflight e teste local sem ferramentas…";
        if (localModelStatus != null) {
            localModelStatus.setText(localModelMessage);
        }
        refreshLocalModelButtons();
        setControlsEnabled(false);
        status.setText("Testando modelo local…");

        runtimeExecutor.submit(() -> {
            final long totalStartedMs =
                android.os.SystemClock.elapsedRealtime();
            try {
                LaboratoryAiLocalModelCatalog.Model model =
                    LaboratoryAiLocalModelCatalog.resolve(
                        getFilesDir(), selected);
                LaboratoryAiLocalModelAdmission.AdmittedModel admitted =
                    LaboratoryAiLocalModelAdmission.admit(
                        getFilesDir(), model.modelFile);
                LaboratoryAiLocalModelPreflight.Report preflight =
                    LaboratoryAiLocalModelPreflight.inspect(
                        this, admitted);

                if (!preflight.canAttemptLoad) {
                    throw new java.io.IOException(
                        "preflight bloqueou a carga: "
                            + preflight.signalCodes);
                }

                final String runtimeVersion;
                final String modelDescription;
                final String rawOutput;
                final long runtimeModelBytes;
                final long loadMs;
                final long generationMs;
                long loadStartedMs =
                    android.os.SystemClock.elapsedRealtime();
                try (LaboratoryAiLlamaCppBackend backend =
                        LaboratoryAiLocalModelPreflight.open(
                            this,
                            model.modelFile,
                            LaboratoryAiLlamaCppBackend.RuntimeConfig
                                .smokeTestDefaults())) {
                    loadMs = Math.max(
                        0L,
                        android.os.SystemClock.elapsedRealtime()
                            - loadStartedMs);
                    runtimeVersion = backend.runtimeVersion();
                    modelDescription = backend.modelDescription();
                    runtimeModelBytes = backend.modelSizeBytes();

                    long generationStartedMs =
                        android.os.SystemClock.elapsedRealtime();
                    rawOutput = backend.generate(
                        new LaboratoryAiLocalModelBackend.GenerationRequest(
                            "Return exactly one JSON object and no markdown: "
                                + "{\"cafeina\":\"ok\","
                                + "\"purpose\":"
                                + "\"local_model_smoke_test\"}",
                            2048,
                            0.0f,
                            20261001L));
                    generationMs = Math.max(
                        0L,
                        android.os.SystemClock.elapsedRealtime()
                            - generationStartedMs);
                }
                final long totalMs = Math.max(
                    0L,
                    android.os.SystemClock.elapsedRealtime()
                        - totalStartedMs);

                boolean exactDiagnostic = false;
                try {
                    JSONObject parsed = new JSONObject(rawOutput.trim());
                    exactDiagnostic =
                        "ok".equals(parsed.optString("cafeina"))
                            && "local_model_smoke_test".equals(
                                parsed.optString("purpose"));
                } catch (Exception ignored) {
                    exactDiagnostic = false;
                }

                final boolean diagnosticOk = exactDiagnostic;
                final String output = rawOutput;
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    localModelRuntimeInProgress = false;
                    localModelMessage =
                        diagnosticOk
                            ? "Modelo carregado e inferência diagnóstica OK."
                            : "Modelo gerou texto, mas não respeitou o JSON diagnóstico.";
                    if (localModelStatus != null) {
                        localModelStatus.setText(localModelMessage);
                    }
                    refreshLocalModelButtons();
                    setControlsEnabled(true);
                    refreshAutoExecButton();
                    status.setText(
                        diagnosticOk
                            ? "Teste do modelo local concluído"
                            : "Inferência concluída com formato inesperado");

                    new AlertDialog.Builder(this)
                        .setTitle(
                            diagnosticOk
                                ? "Modelo local funcionando"
                                : "Modelo respondeu")
                        .setMessage(
                            "Preflight: " + preflight.status
                                + "\nRuntime: " + runtimeVersion
                                + "\nModelo: " + modelDescription
                                + "\nArquivo GGUF: "
                                + modelSizeLabel(preflight.modelSizeBytes)
                                + "\nModelo reportado pelo runtime: "
                                + modelSizeLabel(runtimeModelBytes)
                                + "\nRAM disponível: "
                                + modelSizeLabel(preflight.availableRamBytes)
                                + " / "
                                + modelSizeLabel(preflight.totalRamBytes)
                                + "\nCarga: " + loadMs + " ms"
                                + "\nGeração: " + generationMs + " ms"
                                + "\nTotal do teste: " + totalMs + " ms"
                                + "\nPerfil smoke: 32 tokens • contexto 1024 • timeout 90 s"
                                + "\n\nSaída diagnóstica:\n"
                                + output)
                        .setPositiveButton("OK", null)
                        .show();
                });
            } catch (Exception error) {
                final long failedAfterMs = Math.max(
                    0L,
                    android.os.SystemClock.elapsedRealtime()
                        - totalStartedMs);
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    localModelRuntimeInProgress = false;
                    localModelMessage =
                        "Teste local falhou após "
                            + failedAfterMs
                            + " ms: "
                            + String.valueOf(error.getMessage());
                    if (localModelStatus != null) {
                        localModelStatus.setText(localModelMessage);
                    }
                    refreshLocalModelButtons();
                    setControlsEnabled(true);
                    refreshAutoExecButton();
                    status.setText("Falha no teste do modelo local");
                    new AlertDialog.Builder(this)
                        .setTitle("Modelo local não testado")
                        .setMessage(
                            "Nenhuma ferramenta ou plano foi executado."
                                + "\nTempo até a falha: "
                                + failedAfterMs + " ms"
                                + "\nPerfil: 32 tokens • contexto 1024 • timeout 90 s"
                                + "\n\n"
                                + String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
                        .show();
                });
            }
        });
    }

    private void refreshLocalModelButtons() {
        boolean idle =
            !localModelImportInProgress && !localModelRuntimeInProgress;
        if (localModelImportButton != null) {
            localModelImportButton.setEnabled(idle);
        }
        if (localModelSelectButton != null) {
            localModelSelectButton.setEnabled(idle);
        }
        if (localModelTestButton != null) {
            localModelTestButton.setText(
                localModelRuntimeInProgress
                    ? "TESTANDO MODELO…"
                    : "TESTAR MODELO LOCAL");
            localModelTestButton.setEnabled(
                idle && !selectedLocalModelFileName().isEmpty());
        }
    }

    private static String modelSizeLabel(long bytes) {
        if (bytes >= 1024L * 1024L * 1024L) {
            return String.format(
                java.util.Locale.ROOT,
                "%.2f GiB",
                bytes / (1024.0 * 1024.0 * 1024.0));
        }
        if (bytes >= 1024L * 1024L) {
            return String.format(
                java.util.Locale.ROOT,
                "%.1f MiB",
                bytes / (1024.0 * 1024.0));
        }
        if (bytes >= 1024L) {
            return String.format(
                java.util.Locale.ROOT,
                "%.1f KiB",
                bytes / 1024.0);
        }
        return bytes + " B";
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode == REQUEST_IMPORT_LOCAL_MODEL) {
            if (resultCode == RESULT_OK
                    && data != null
                    && data.getData() != null) {
                importLocalModel(data.getData());
            }
            return;
        }

        if ((requestCode != REQUEST_EXPORT_ARCHIVE && requestCode != REQUEST_IMPORT_ARCHIVE)
                || resultCode != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        if (!requireSavedForArchive()) return;

        final Uri document = data.getData();
        final ScriptStore targetStore = scriptStore;
        setControlsEnabled(false);
        status.setText(requestCode == REQUEST_EXPORT_ARCHIVE
            ? "Exportando scripts…" : "Importando scripts…");
        ioExecutor.submit(() -> {
            try {
                if (requestCode == REQUEST_EXPORT_ARCHIVE) {
                    try (OutputStream output = getContentResolver().openOutputStream(document, "w")) {
                        if (output == null) throw new java.io.IOException("O arquivo de destino não abriu.");
                        int count = ScriptArchive.exportScripts(targetStore, output);
                        runOnUiThread(() -> {
                            if (!activityAlive()) return;
                            status.setText("Backup concluído • " + count + " script(s)");
                            console.setText("ZIP salvo no local escolhido. Os arquivos originais não foram alterados.");
                            setControlsEnabled(true);
                            refreshAutoExecButton();
                        });
                    }
                } else {
                    final ScriptArchive.ImportResult imported;
                    try (InputStream input = getContentResolver().openInputStream(document)) {
                        if (input == null) throw new java.io.IOException("Não foi possível abrir o ZIP.");
                        imported = ScriptArchive.importScripts(targetStore, input);
                    }
                    final Map<String, String> importedContents = new LinkedHashMap<>();
                    for (String name : imported.names()) {
                        importedContents.put(name, targetStore.load(name));
                    }
                    runOnUiThread(() -> {
                        if (!activityAlive()) return;
                        for (Map.Entry<String, String> script : importedContents.entrySet()) {
                            editorHistory.forget(script.getKey());
                            tabs.openOrReplace(script.getKey(), script.getValue());
                        }
                        refreshHistoryButtons();
                        if (!importedContents.isEmpty()) {
                            setEditorText(tabs.activeContent());
                            renderTabs();
                        }
                        status.setText("Importados " + imported.names().size() + " script(s); "
                            + imported.renamedCount() + " renomeado(s)");
                        setControlsEnabled(true);
                        refreshAutoExecButton();
                    });
                }
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    status.setText("Falha no ZIP; os scripts salvos não foram apagados");
                    console.setText("[ARQUIVO ZIP] " + error.getMessage());
                    setControlsEnabled(true);
                    refreshAutoExecButton();
                });
            }
        });
    }

    private void restoreSavedTabs() {
        setControlsEnabled(false);
        status.setText("Restaurando scripts locais...");

        ioExecutor.submit(() -> {
            final Map<String, String> loaded = new LinkedHashMap<>();
            int failures = 0;

            try {
                List<String> names = scriptStore.listScripts();
                for (String name : names) {
                    try {
                        loaded.put(name, scriptStore.load(name));
                    } catch (Exception ignored) {
                        failures++;
                    }
                }
            } catch (Exception error) {
                final Exception failure = error;
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    setControlsEnabled(true);
                    showStorageError("Falha ao restaurar scripts", failure);
                });
                return;
            }

            final int failedCount = failures;
            runOnUiThread(() -> {
                if (!activityAlive()) return;

                int firstLoadedIndex = -1;
                for (Map.Entry<String, String> entry : loaded.entrySet()) {
                    int index = tabs.openOrReplace(entry.getKey(), entry.getValue());
                    if (firstLoadedIndex < 0) firstLoadedIndex = index;
                }

                if (firstLoadedIndex >= 0) {
                    tabs.activate(firstLoadedIndex);
                }

                setEditorText(tabs.activeContent());
                renderTabs();
                setControlsEnabled(true);

                if (loaded.isEmpty() && failedCount == 0) {
                    status.setText("Pronto • " + tabs.activeName());
                } else if (failedCount == 0) {
                    status.setText("Restaurados " + loaded.size() + " script(s) • " + tabs.activeName());
                } else {
                    status.setText(
                        "Restaurados " + loaded.size() + " • falhas " + failedCount + " • " + tabs.activeName()
                    );
                }

                refreshAutoExecButton();
                runAutoExecOnStartup();
            });
        });
    }

    private void setControlsEnabled(boolean enabled) {
        editor.setEnabled(enabled);
        executeButton.setEnabled(enabled);
        clearButton.setEnabled(enabled);
        saveButton.setEnabled(enabled);
        loadButton.setEnabled(enabled);
        if (autoExecuteButton != null) autoExecuteButton.setEnabled(enabled);
        if (addTabButton != null) addTabButton.setEnabled(enabled);
        refreshHistoryButtons();
    }

    private void refreshHistoryButtons() {
        if (undoButton == null || redoButton == null || editor == null) return;
        boolean editable = editor.isEnabled();
        undoButton.setEnabled(editable && editorHistory.canUndo(tabs.activeName()));
        redoButton.setEnabled(editable && editorHistory.canRedo(tabs.activeName()));
    }

    private void restoreEditorHistory(boolean redo) {
        if (!editor.isEnabled()) return;
        String name = tabs.activeName();
        String current = editor.getText().toString();
        if (redo ? !editorHistory.canRedo(name) : !editorHistory.canUndo(name)) return;
        String restored = redo ? editorHistory.redo(name, current) : editorHistory.undo(name, current);
        setEditorText(restored);
        tabs.updateActiveContent(restored);
        renderTabs();
        refreshAutoExecButton();
        refreshHistoryButtons();
        status.setText((redo ? "Refeito • " : "Desfeito • ") + name);
    }

    private void addTwoButtons(LinearLayout row, Button left, Button right) {
        LinearLayout.LayoutParams leftParams =
            new LinearLayout.LayoutParams(0, dp(44), 1f);
        leftParams.setMargins(0, 0, dp(5), 0);
        row.addView(left, leftParams);

        LinearLayout.LayoutParams rightParams =
            new LinearLayout.LayoutParams(0, dp(44), 1f);
        rightParams.setMargins(dp(5), 0, 0, 0);
        row.addView(right, rightParams);
    }

    private void renderTabs() {
        if (tabButtons == null) return;
        tabButtons.removeAllViews();

        for (int i = 0; i < tabs.size(); i++) {
            final int index = i;
            boolean active = i == tabs.activeIndex();

            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.HORIZONTAL);

            String label = tabs.nameAt(i) + (tabs.isDirtyAt(i) ? " *" : "");
            Button tab = makeTabButton(label, active);
            tab.setMaxWidth(dp(192));
            tab.setSingleLine(true);
            tab.setEllipsize(TextUtils.TruncateAt.MIDDLE);
            tab.setContentDescription(label);
            tab.setOnClickListener(v -> switchTab(index));

            Button close = makeTabButton("×", false);
            close.setMinWidth(dp(40));
            close.setEnabled(tabs.size() > 1);
            close.setOnClickListener(v -> requestCloseTab(index));

            item.addView(tab, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(38)
            ));
            item.addView(close, new LinearLayout.LayoutParams(
                dp(40),
                dp(38)
            ));

            LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(38));
            params.setMargins(0, 0, dp(6), 0);
            tabButtons.addView(item, params);
        }

        addTabButton = makeTabButton("+", false);
        addTabButton.setMinWidth(dp(48));
        addTabButton.setOnClickListener(v -> addTab());
        tabButtons.addView(addTabButton, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(38)
        ));

        // Keep the current script visible after opening, restoring or switching tabs.
        final android.view.View activeTab = tabButtons.getChildAt(tabs.activeIndex());
        if (tabScroll != null && activeTab != null) {
            tabScroll.post(() -> {
                if (activeTab.getParent() != tabButtons || tabScroll.getWidth() == 0) return;
                int left = activeTab.getLeft();
                int right = activeTab.getRight();
                int start = tabScroll.getScrollX();
                int visible = tabScroll.getWidth();
                if (left < start) tabScroll.smoothScrollTo(Math.max(0, left - dp(8)), 0);
                else if (right > start + visible) {
                    tabScroll.smoothScrollTo(Math.max(0, right - visible + dp(8)), 0);
                }
            });
        }
    }

    private void switchTab(int index) {
        if (index == tabs.activeIndex()) return;

        tabs.updateActiveContent(editor.getText().toString());
        tabs.activate(index);
        showActiveTab("Pronto");
    }

    private void addTab() {
        tabs.updateActiveContent(editor.getText().toString());
        addTabButton.setEnabled(false);
        status.setText("Verificando nomes salvos...");

        ioExecutor.submit(() -> {
            try {
                List<String> savedNames = scriptStore.listScripts();
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    String name = tabs.addTab(new HashSet<>(savedNames));
                    setEditorText("");
                    status.setText("Nova aba • " + name);
                    renderTabs();
                    refreshAutoExecButton();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    if (addTabButton != null) addTabButton.setEnabled(true);
                    showStorageError("Não foi possível criar a aba", error);
                });
            }
        });
    }

    private void requestCloseTab(int index) {
        tabs.updateActiveContent(editor.getText().toString());

        if (tabs.size() <= 1) {
            status.setText("Mantenha ao menos uma aba aberta");
            return;
        }

        final String name = tabs.nameAt(index);
        if (!tabs.isDirtyAt(index)) {
            closeTabNow(name);
            return;
        }

        new AlertDialog.Builder(this)
            .setTitle("Alterações não salvas")
            .setMessage(name + " possui alterações que ainda não foram salvas.")
            .setPositiveButton("Salvar e fechar", (dialog, which) -> saveAndCloseTab(name))
            .setNeutralButton("Fechar sem salvar", (dialog, which) -> closeTabNow(name))
            .setNegativeButton("Cancelar", null)
            .show();
    }

    private void saveAndCloseTab(String name) {
        int index = tabs.indexOfName(name);
        if (index < 0) return;

        final String content = tabs.contentAt(index);
        status.setText("Salvando antes de fechar • " + name);

        ioExecutor.submit(() -> {
            try {
                scriptStore.save(name, content);
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    tabs.markSaved(name, content);
                    int currentIndex = tabs.indexOfName(name);
                    if (currentIndex >= 0 && tabs.isDirtyAt(currentIndex)) {
                        renderTabs();
                        status.setText("Versão anterior salva • alterações recentes mantidas em " + name);
                        return;
                    }
                    closeTabNow(name);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    showStorageError("Falha ao salvar antes de fechar " + name, error);
                });
            }
        });
    }

    private void closeTabNow(String name) {
        int index = tabs.indexOfName(name);
        if (index < 0) return;
        if (tabs.size() <= 1) {
            status.setText("Mantenha ao menos uma aba aberta");
            return;
        }

        tabs.close(index);
        editorHistory.forget(name);
        showActiveTab("Aba fechada");
    }

    private void clearActiveTab() {
        if (editor.getText().length() == 0) {
            console.setText("");
            status.setText("Editor já está vazio • " + tabs.activeName());
            return;
        }
        final String name = tabs.activeName();
        final boolean undoAvailable = editor.getText().length()
            <= EditorUndoHistory.MAX_SNAPSHOT_CHARS;
        String warning = undoAvailable
            ? "O conteúdo de " + name + " será apagado do editor. Você poderá usar DESFAZER."
            : "Este código é grande demais para o histórico em memória. DESFAZER não recuperará "
                + "o texto apagado. Salve uma cópia antes de limpar.";
        new AlertDialog.Builder(this)
            .setTitle("Limpar o código?")
            .setMessage(warning + " O arquivo salvo em disco não será excluído.")
            .setPositiveButton(undoAvailable ? "Limpar" : "Limpar mesmo assim", (dialog, which) -> {
                if (!name.equals(tabs.activeName())) return;
                editorHistory.record(name, editor.getText().toString(), "");
                setEditorText("");
                tabs.updateActiveContent("");
                console.setText("");
                renderTabs();
                refreshAutoExecButton();
                refreshHistoryButtons();
                status.setText("Editor limpo • " + name + (editorHistory.canUndo(name)
                    ? " (DESFAZER recupera o código)" : " (arquivo salvo preservado)"));
            })
            .setNegativeButton("Cancelar", null)
            .show();
    }

    private void saveActiveScript() {
        final String name = tabs.activeName();
        final String content = editor.getText().toString();
        tabs.updateActiveContent(content);

        saveButton.setEnabled(false);
        status.setText("Salvando • " + name);

        ioExecutor.submit(() -> {
            try {
                scriptStore.save(name, content);
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    tabs.markSaved(name, content);
                    saveButton.setEnabled(true);
                    renderTabs();
                    refreshAutoExecButton();
                    status.setText("Salvo localmente • " + name);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    saveButton.setEnabled(true);
                    showStorageError("Falha ao salvar " + name, error);
                });
            }
        });
    }

    private void showLoadPicker() {
        tabs.updateActiveContent(editor.getText().toString());
        loadButton.setEnabled(false);
        status.setText("Lendo scripts locais...");

        ioExecutor.submit(() -> {
            try {
                List<String> names = scriptStore.listScripts();
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    loadButton.setEnabled(true);

                    if (names.isEmpty()) {
                        status.setText("Nenhum script salvo");
                        return;
                    }

                    String[] items = names.toArray(new String[0]);
                    new AlertDialog.Builder(this)
                        .setTitle("LOAD SCRIPT")
                        .setItems(items, (dialog, which) -> loadScript(items[which]))
                        .setNegativeButton("Cancelar", null)
                        .show();

                    status.setText(names.size() + " script(s) local(is)");
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    loadButton.setEnabled(true);
                    showStorageError("Falha ao listar scripts", error);
                });
            }
        });
    }

    private void loadScript(String name) {
        loadButton.setEnabled(false);
        status.setText("Carregando • " + name);

        ioExecutor.submit(() -> {
            try {
                String diskContent = scriptStore.load(name);
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    confirmOrApplyLoadedScript(name, diskContent);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    loadButton.setEnabled(true);
                    showStorageError("Falha ao carregar " + name, error);
                });
            }
        });
    }

    private void confirmOrApplyLoadedScript(String name, String diskContent) {
        tabs.updateActiveContent(editor.getText().toString());

        int existing = tabs.indexOfName(name);
        if (
            existing >= 0
                && tabs.isDirtyAt(existing)
                && !tabs.contentAt(existing).equals(diskContent)
        ) {
            new AlertDialog.Builder(this)
                .setTitle("Substituir conteúdo?")
                .setMessage(
                    name
                        + " já está aberto com alterações não salvas. "
                        + "Carregar a versão salva substituirá essas alterações em memória."
                )
                .setPositiveButton("Carregar", (dialog, which) -> applyLoadedScript(name, diskContent))
                .setNegativeButton("Cancelar", (dialog, which) -> {
                    loadButton.setEnabled(true);
                    status.setText("Carga cancelada • " + name);
                })
                .setOnCancelListener(dialog -> {
                    loadButton.setEnabled(true);
                    status.setText("Carga cancelada • " + name);
                })
                .show();
            return;
        }

        applyLoadedScript(name, diskContent);
    }

    private void applyLoadedScript(String name, String diskContent) {
        editorHistory.forget(name);
        tabs.openOrReplace(name, diskContent);
        setEditorText(tabs.activeContent());
        loadButton.setEnabled(true);
        status.setText("Carregado localmente • " + name);
        refreshHistoryButtons();
        renderTabs();
        refreshAutoExecButton();
    }

    private void toggleAutoExecute() {
        tabs.updateActiveContent(editor.getText().toString());

        final String name = tabs.activeName();
        if (tabs.activeDirty()) {
            status.setText("Salve as alterações antes de ativar Auto Execute • " + name);
            refreshAutoExecButton();
            return;
        }

        autoExecuteButton.setEnabled(false);
        status.setText("Atualizando Auto Execute • " + name);

        ioExecutor.submit(() -> {
            try {
                if (!scriptStore.exists(name)) {
                    runOnUiThread(() -> {
                        if (!activityAlive()) return;
                        status.setText("Salve o script antes de ativar Auto Execute • " + name);
                        refreshAutoExecButton();
                    });
                    return;
                }

                boolean next = !autoExecuteStore.isEnabled(name);
                autoExecuteStore.setEnabled(name, next);

                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    status.setText((next ? "Auto Execute ativado • " : "Auto Execute desativado • ") + name);
                    refreshAutoExecButton();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    showStorageError("Falha ao atualizar Auto Execute de " + name, error);
                    refreshAutoExecButton();
                });
            }
        });
    }

    private void refreshAutoExecButton() {
        if (autoExecuteButton == null || tabs.size() == 0) return;

        final String name = tabs.activeName();
        final boolean dirty = tabs.activeDirty();

        if (dirty) {
            autoExecuteButton.setText("AUTOEXEC: SAVE CHANGES");
            autoExecuteButton.setEnabled(false);
            return;
        }

        autoExecuteButton.setText("AUTOEXEC: CHECKING");
        autoExecuteButton.setEnabled(false);

        ioExecutor.submit(() -> {
            try {
                boolean exists = scriptStore.exists(name);
                boolean enabled = exists && autoExecuteStore.isEnabled(name);

                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    if (!tabs.activeName().equals(name) || tabs.activeDirty()) return;

                    if (!exists) {
                        autoExecuteButton.setText("AUTOEXEC: SAVE FIRST");
                        autoExecuteButton.setEnabled(false);
                    } else {
                        autoExecuteButton.setText(enabled ? "AUTOEXEC: ON" : "AUTOEXEC: OFF");
                        autoExecuteButton.setEnabled(true);
                    }
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    if (!tabs.activeName().equals(name)) return;
                    autoExecuteButton.setText("AUTOEXEC: ERROR");
                    autoExecuteButton.setEnabled(false);
                });
            }
        });
    }

    private void runAutoExecOnStartup() {
        if (autoExecStartupTriggered) return;
        autoExecStartupTriggered = true;

        ioExecutor.submit(() -> {
            final Map<String, String> sources = new LinkedHashMap<>();
            final StringBuilder preloadReport = new StringBuilder();

            try {
                List<String> enabled = autoExecuteStore.enabledScripts();
                if (enabled.isEmpty()) return;

                for (String name : enabled) {
                    try {
                        if (!scriptStore.exists(name)) {
                            preloadReport
                                .append("[AUTOEXEC] ")
                                .append(name)
                                .append("\n[SKIP] arquivo salvo não encontrado\n\n");
                            continue;
                        }
                        sources.put(name, scriptStore.load(name));
                    } catch (Exception error) {
                        preloadReport
                            .append("[AUTOEXEC] ")
                            .append(name)
                            .append("\n[LOAD ERROR] ")
                            .append(String.valueOf(error.getMessage()))
                            .append("\n\n");
                    }
                }
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    showStorageError("Falha ao preparar Auto Execute", error);
                });
                return;
            }

            if (sources.isEmpty()) {
                if (preloadReport.length() > 0) {
                    runOnUiThread(() -> {
                        if (!activityAlive()) return;
                        console.setText(preloadReport.toString().trim());
                        status.setText("Auto Execute sem scripts executáveis");
                    });
                }
                return;
            }

            runOnUiThread(() -> {
                if (!activityAlive()) return;
                executeButton.setEnabled(false);
                status.setText("Auto Execute • " + sources.size() + " script(s)");
            });

            runtimeExecutor.submit(() -> {
                StringBuilder report = new StringBuilder(preloadReport);
                int success = 0;
                int failed = 0;

                for (Map.Entry<String, String> entry : sources.entrySet()) {
                    String name = entry.getKey();
                    report.append("[AUTOEXEC] ").append(name).append('\n');

                    try {
                        String raw = LuauBridge.nativeExecuteWithFiles(entry.getValue(), 500, runtimeFilesRoot);
                        JSONObject result = new JSONObject(raw);
                        boolean ok = result.optBoolean("ok", false);
                        String output = result.optString("output", "");
                        String error = result.optString("error", "");
                        JSONArray returns = result.optJSONArray("returns");

                        if (!output.isEmpty()) {
                            report.append(output);
                            if (!output.endsWith("\n")) report.append('\n');
                        }

                        if (ok) {
                            success++;
                            if (returns != null && returns.length() > 0) {
                                report.append("returns:");
                                for (int i = 0; i < returns.length(); i++) {
                                    report.append(" [").append(returns.optString(i)).append(']');
                                }
                                report.append('\n');
                            }
                        } else {
                            failed++;
                            report.append("[ERRO] ").append(error).append('\n');
                        }
                    } catch (Throwable error) {
                        failed++;
                        report
                            .append("[BRIDGE ERROR] ")
                            .append(String.valueOf(error.getMessage()))
                            .append('\n');
                    }

                    report.append('\n');
                }

                final int okCount = success;
                final int failCount = failed;
                final String rendered = report.toString().trim();

                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    console.setText(rendered);
                    status.setText(
                        "Auto Execute concluído • ok " + okCount + " • falhas " + failCount
                    );
                    executeButton.setEnabled(true);
                });
            });
        });
    }

    private void executeSource() {
        final String source = editor.getText().toString();
        tabs.updateActiveContent(source);

        if (source.trim().isEmpty()) {
            console.setText("[ERRO]\nO editor está vazio.");
            status.setText("Nada para executar • " + tabs.activeName());
            return;
        }

        final String tabName = tabs.activeName();
        executeButton.setEnabled(false);
        status.setText("Executando • " + tabName);
        console.setText("");

        runtimeExecutor.submit(() -> {
            try {
                final String raw = LuauBridge.nativeExecuteWithFiles(source, 500, runtimeFilesRoot);
                runOnUiThread(() -> renderResult(raw, tabName));
            } catch (Throwable error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    console.setText("[BRIDGE ERROR]\n" + String.valueOf(error.getMessage()));
                    status.setText("Erro na bridge • " + tabName);
                    executeButton.setEnabled(true);
                });
            }
        });
    }

    private void renderResult(String raw, String tabName) {
        try {
            JSONObject result = new JSONObject(raw);
            boolean ok = result.optBoolean("ok", false);
            String output = result.optString("output", "");
            String error = result.optString("error", "");
            long elapsedMs = result.optLong("elapsedMs", 0);
            JSONArray returns = result.optJSONArray("returns");

            StringBuilder rendered = new StringBuilder();
            if (!output.isEmpty()) {
                rendered.append(output);
                if (!output.endsWith("\n")) rendered.append('\n');
            }

            if (ok) {
                if (rendered.length() == 0) rendered.append("OK\n");
                if (returns != null && returns.length() > 0) {
                    rendered.append("returns:");
                    for (int i = 0; i < returns.length(); i++) {
                        rendered.append(" [").append(returns.optString(i)).append(']');
                    }
                    rendered.append('\n');
                }
                status.setText("Concluído • " + tabName + " • " + elapsedMs + " ms");
            } else {
                rendered.append("[ERRO]\n").append(error).append('\n');
                status.setText("Falhou • " + tabName + " • " + elapsedMs + " ms");
            }

            console.setText(rendered.toString().trim());
        } catch (Exception parseError) {
            console.setText("[JSON ERROR]\n" + parseError.getMessage() + "\n\nRaw:\n" + raw);
            status.setText("Resposta inválida • " + tabName);
        } finally {
            executeButton.setEnabled(true);
        }
    }

    private void showActiveTab(String prefix) {
        setEditorText(tabs.activeContent());
        status.setText(prefix + " • " + tabs.activeName());
        renderTabs();
        refreshAutoExecButton();
        refreshHistoryButtons();
    }

    private void setEditorText(String value) {
        suppressEditorWatcher = true;
        editor.setText(value == null ? "" : value);
        editor.setSelection(editor.length());
        suppressEditorWatcher = false;
    }

    private void showStorageError(String prefix, Exception error) {
        String detail = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
        console.setText("[STORAGE ERROR]\n" + prefix + "\n" + detail);
        status.setText("Erro de armazenamento");
    }

    private boolean activityAlive() {
        return !isFinishing() && !isDestroyed();
    }

    private Button makeButton(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(Color.WHITE);
        button.setTextSize(14);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackgroundTintList(ColorStateList.valueOf(color));
        return button;
    }

    private Button makeTabButton(String label, boolean active) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTextSize(13);
        button.setTypeface(Typeface.MONOSPACE, active ? Typeface.BOLD : Typeface.NORMAL);
        button.setMinWidth(dp(96));
        button.setPadding(dp(10), 0, dp(10), 0);
        button.setBackgroundTintList(ColorStateList.valueOf(active ? ACCENT : PANEL_2));
        return button;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        if (editor != null && tabs.size() > 0) {
            tabs.updateActiveContent(editor.getText().toString());
        }
        if (aiChatPanel != null) {
            aiChatPanel.close();
        }
        runtimeExecutor.shutdownNow();
        ioExecutor.shutdownNow();
        super.onDestroy();
    }
}
