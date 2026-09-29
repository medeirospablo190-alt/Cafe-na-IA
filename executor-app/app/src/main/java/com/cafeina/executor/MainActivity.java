package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
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
    private static final String DEFAULT_SOURCE = "print(\"Olá do CAFEÍNA\")\nreturn 6 * 7";

    private final ExecutorService runtimeExecutor = Executors.newSingleThreadExecutor();
    private final ExecutorService ioExecutor = Executors.newSingleThreadExecutor();
    private final EditorTabs tabs = new EditorTabs(DEFAULT_SOURCE);

    private ScriptStore scriptStore;
    private AutoExecuteStore autoExecuteStore;
    private String runtimeFilesRoot;
    private EditText editor;
    private TextView console;
    private TextView status;
    private Button executeButton;
    private Button clearButton;
    private Button saveButton;
    private Button loadButton;
    private Button autoExecuteButton;
    private Button addTabButton;
    private LinearLayout tabButtons;
    private boolean suppressEditorWatcher;
    private boolean autoExecStartupTriggered;
    private LinearLayout screenHost;
    private LinearLayout codeScreen;
    private final Map<String, Button> navigation = new LinkedHashMap<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        scriptStore = new ScriptStore(getFilesDir());
        autoExecuteStore = new AutoExecuteStore(getFilesDir());
        runtimeFilesRoot = getFilesDir().toPath().resolve("runtime-fs").toString();
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        setContentView(buildAppUi());
        restoreSavedTabs();
    }


    // Product shell: the editor stays alive when moving between sections.
    private LinearLayout buildAppUi() {
        LinearLayout app = new LinearLayout(this);
        app.setOrientation(LinearLayout.VERTICAL);
        app.setBackgroundColor(BG);

        TextView brand = new TextView(this);
        brand.setText("CAFEÍNA");
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
        if ("SISTEMA".equals(name)) {
            startActivity(new Intent(this, ProjectManagerActivity.class));
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
        if ("MUNDO".equals(name)) {
            detail.setText("A integração do mundo Godot já validado no T14 ainda não foi incorporada a este APK. O desenvolvimento será feito aqui no aplicativo, sem outra sequência de testes no editor do Godot.");
        } else if ("3D".equals(name)) {
            detail.setText("O módulo de criação e edição 3D ainda está em desenvolvimento. Nenhuma alteração será feita nos seus scripts ao entrar nesta área.");
        } else {
            detail.setText("A IA local ainda não foi integrada. A execução Luau, o editor e o armazenamento privado já estão disponíveis na aba CÓDIGO.");
        }
        section.addView(detail, matchWrap());

        Button back = makeButton("VOLTAR AO CÓDIGO", ACCENT);
        back.setOnClickListener(v -> showSection("CÓDIGO"));
        section.addView(back, matchWrap());
        screenHost.addView(section,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
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
        subtitle.setText("Scripts locais • VM Luau isolada");
        subtitle.setTextColor(MUTED);
        subtitle.setTextSize(11);
        LinearLayout.LayoutParams subtitleParams = matchWrap();
        subtitleParams.setMargins(0, dp(2), 0, dp(8));
        root.addView(subtitle, subtitleParams);

        HorizontalScrollView tabScroll = new HorizontalScrollView(this);
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

        editor = new EditText(this);
        editor.setText(tabs.activeContent());
        editor.setTextColor(TEXT);
        editor.setHintTextColor(MUTED);
        editor.setBackgroundColor(PANEL);
        editor.setTypeface(Typeface.MONOSPACE);
        editor.setTextSize(17);
        editor.setGravity(Gravity.TOP | Gravity.START);
        editor.setPadding(dp(12), dp(12), dp(12), dp(12));
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
                tabs.updateActiveContent(value.toString());
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

        renderTabs();
        return root;
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
        showActiveTab("Aba fechada");
    }

    private void clearActiveTab() {
        setEditorText("");
        tabs.updateActiveContent("");
        console.setText("");
        renderTabs();
        refreshAutoExecButton();
        status.setText("Editor limpo • " + tabs.activeName());
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
        tabs.openOrReplace(name, diskContent);
        setEditorText(tabs.activeContent());
        loadButton.setEnabled(true);
        status.setText("Carregado localmente • " + name);
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
        runtimeExecutor.shutdownNow();
        ioExecutor.shutdownNow();
        super.onDestroy();
    }
}
