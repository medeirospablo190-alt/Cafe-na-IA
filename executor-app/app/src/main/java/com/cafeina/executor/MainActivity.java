package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
    private final Set<String> autoExecuteNames = new LinkedHashSet<>();

    private ScriptStore scriptStore;
    private AutoExecuteStore autoExecuteStore;
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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        scriptStore = new ScriptStore(getFilesDir());
        autoExecuteStore = new AutoExecuteStore(getFilesDir());
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        setContentView(buildUi());
        restoreSavedTabs();
    }

    private LinearLayout buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(14), dp(14), dp(14), dp(14));
        root.setBackgroundColor(BG);

        TextView title = new TextView(this);
        title.setText("CAFEÍNA • LUAU RUNTIME");
        title.setTextColor(TEXT);
        title.setTextSize(17);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("Phase 7 • local auto execute + safe runtime");
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
        editor.setTextSize(14);
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
                }

                updateAutoExecuteButton();

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

        autoExecuteButton = makeButton("AUTO EXEC: OFF", Color.rgb(78, 82, 101));
        LinearLayout.LayoutParams autoParams =
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(44));
        autoParams.setMargins(0, dp(6), 0, 0);
        root.addView(autoExecuteButton, autoParams);

        status = new TextView(this);
        status.setText("Preparando...");
        status.setTextColor(MUTED);
        status.setTextSize(11);
        LinearLayout.LayoutParams statusParams = matchWrap();
        statusParams.setMargins(0, dp(8), 0, dp(6));
        root.addView(status, statusParams);

        ScrollView consoleScroll = new ScrollView(this);
        consoleScroll.setFillViewport(true);
        consoleScroll.setBackgroundColor(PANEL_2);

        console = new TextView(this);
        console.setText("Console aguardando execução.");
        console.setTextColor(TEXT);
        console.setTextSize(12);
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
        updateAutoExecuteButton();
        return root;
    }

    private void restoreSavedTabs() {
        setControlsEnabled(false);
        status.setText("Restaurando scripts locais...");

        ioExecutor.submit(() -> {
            final Map<String, String> loaded = new LinkedHashMap<>();
            final Set<String> configuredAutoExecute = new LinkedHashSet<>();
            int failures = 0;
            boolean autoConfigFailure = false;

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

            try {
                configuredAutoExecute.addAll(autoExecuteStore.load());
            } catch (Exception ignored) {
                autoConfigFailure = true;
            }

            final Set<String> validAutoExecute = new LinkedHashSet<>();
            for (String name : configuredAutoExecute) {
                if (loaded.containsKey(name)) {
                    validAutoExecute.add(name);
                }
            }

            if (!validAutoExecute.equals(configuredAutoExecute)) {
                try {
                    autoExecuteStore.save(validAutoExecute);
                } catch (Exception ignored) {
                    autoConfigFailure = true;
                }
            }

            final int failedCount = failures;
            final boolean configFailed = autoConfigFailure;
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

                autoExecuteNames.clear();
                autoExecuteNames.addAll(validAutoExecute);

                setEditorText(tabs.activeContent());
                renderTabs();
                updateAutoExecuteButton();
                setControlsEnabled(true);

                if (loaded.isEmpty() && failedCount == 0 && !configFailed) {
                    status.setText("Pronto • " + tabs.activeName());
                } else if (failedCount == 0 && !configFailed) {
                    status.setText("Restaurados " + loaded.size() + " script(s) • " + tabs.activeName());
                } else {
                    status.setText(
                        "Restaurados "
                            + loaded.size()
                            + " • falhas "
                            + (failedCount + (configFailed ? 1 : 0))
                            + " • "
                            + tabs.activeName()
                    );
                }

                runAutoExecuteScripts(loaded);
            });
        });
    }

    private void setControlsEnabled(boolean enabled) {
        editor.setEnabled(enabled);
        executeButton.setEnabled(enabled);
        clearButton.setEnabled(enabled);
        saveButton.setEnabled(enabled);
        loadButton.setEnabled(enabled);
        autoExecuteButton.setEnabled(enabled);
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
                    updateAutoExecuteButton();
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
        updateAutoExecuteButton();
    }

    private void toggleAutoExecute() {
        tabs.updateActiveContent(editor.getText().toString());
        updateAutoExecuteButton();

        final String name = tabs.activeName();
        final boolean currentlyEnabled = autoExecuteNames.contains(name);

        if (!currentlyEnabled && tabs.activeDirty()) {
            status.setText("Salve " + name + " antes de ativar Auto Execute");
            return;
        }

        autoExecuteButton.setEnabled(false);
        status.setText((currentlyEnabled ? "Desativando" : "Ativando") + " Auto Execute • " + name);

        final Set<String> next = new LinkedHashSet<>(autoExecuteNames);
        if (currentlyEnabled) {
            next.remove(name);
        } else {
            next.add(name);
        }

        ioExecutor.submit(() -> {
            try {
                if (!currentlyEnabled && !scriptStore.exists(name)) {
                    runOnUiThread(() -> {
                        if (!activityAlive()) return;
                        autoExecuteButton.setEnabled(true);
                        updateAutoExecuteButton();
                        status.setText("Salve " + name + " antes de ativar Auto Execute");
                    });
                    return;
                }

                autoExecuteStore.save(next);
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    autoExecuteNames.clear();
                    autoExecuteNames.addAll(next);
                    autoExecuteButton.setEnabled(true);
                    updateAutoExecuteButton();
                    status.setText(
                        (currentlyEnabled ? "Auto Execute OFF • " : "Auto Execute ON • ") + name
                    );
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!activityAlive()) return;
                    autoExecuteButton.setEnabled(true);
                    updateAutoExecuteButton();
                    showStorageError("Falha ao alterar Auto Execute de " + name, error);
                });
            }
        });
    }

    private void updateAutoExecuteButton() {
        if (autoExecuteButton == null || tabs.size() == 0) return;

        boolean enabled = autoExecuteNames.contains(tabs.activeName());
        if (enabled && tabs.activeDirty()) {
            autoExecuteButton.setText("AUTO EXEC: ON • SALVE");
        } else {
            autoExecuteButton.setText(enabled ? "AUTO EXEC: ON" : "AUTO EXEC: OFF");
        }
        autoExecuteButton.setBackgroundTintList(
            ColorStateList.valueOf(enabled ? Color.rgb(48, 121, 89) : Color.rgb(78, 82, 101))
        );
    }

    private void runAutoExecuteScripts(Map<String, String> loadedScripts) {
        if (autoExecuteNames.isEmpty()) return;

        final Set<String> names = new LinkedHashSet<>(autoExecuteNames);
        final Map<String, String> scripts = new LinkedHashMap<>(loadedScripts);
        executeButton.setEnabled(false);
        status.setText("Auto Execute • " + names.size() + " script(s)...");

        runtimeExecutor.submit(() -> {
            StringBuilder report = new StringBuilder();
            int executed = 0;

            for (String name : names) {
                String source = scripts.get(name);
                if (source == null) continue;

                executed++;
                report.append("[AUTO EXEC] ").append(name).append('\n');

                try {
                    String raw = LuauBridge.nativeExecute(source, 500);
                    JSONObject result = new JSONObject(raw);

                    String output = result.optString("output", "");
                    String error = result.optString("error", "");
                    JSONArray returns = result.optJSONArray("returns");

                    if (!output.isEmpty()) {
                        report.append(output);
                        if (!output.endsWith("\n")) report.append('\n');
                    }

                    if (result.optBoolean("ok", false)) {
                        if (returns != null && returns.length() > 0) {
                            report.append("returns:");
                            for (int i = 0; i < returns.length(); i++) {
                                report.append(" [").append(returns.optString(i)).append(']');
                            }
                            report.append('\n');
                        }
                    } else {
                        report.append("[ERRO] ").append(error).append('\n');
                    }
                } catch (Throwable error) {
                    report.append("[BRIDGE ERROR] ")
                        .append(error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage())
                        .append('\n');
                }

                report.append('\n');
            }

            final int executedCount = executed;
            final String rendered = report.toString().trim();
            runOnUiThread(() -> {
                if (!activityAlive()) return;
                executeButton.setEnabled(true);
                if (!rendered.isEmpty()) {
                    console.setText(rendered);
                }
                status.setText("Auto Execute concluído • " + executedCount + " script(s)");
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
                final String raw = LuauBridge.nativeExecute(source, 500);
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
        updateAutoExecuteButton();
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
        button.setTextSize(12);
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        button.setBackgroundTintList(ColorStateList.valueOf(color));
        return button;
    }

    private Button makeTabButton(String label, boolean active) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextColor(Color.WHITE);
        button.setTextSize(11);
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
