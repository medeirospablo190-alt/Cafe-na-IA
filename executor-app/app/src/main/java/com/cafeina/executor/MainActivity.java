package com.cafeina.executor;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
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
    private final EditorTabs tabs = new EditorTabs(DEFAULT_SOURCE);

    private EditText editor;
    private TextView console;
    private TextView status;
    private Button executeButton;
    private LinearLayout tabButtons;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        setContentView(buildUi());
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
        subtitle.setText("Phase 3 • tabs → editor → runtime → console");
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
        LinearLayout.LayoutParams editorParams =
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        editorParams.setMargins(0, 0, 0, dp(10));
        root.addView(editor, editorParams);

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);

        executeButton = makeButton("EXECUTE", ACCENT);
        Button clearButton = makeButton("CLEAR", Color.rgb(61, 66, 81));

        LinearLayout.LayoutParams actionParams =
            new LinearLayout.LayoutParams(0, dp(46), 1f);
        actionParams.setMargins(0, 0, dp(5), 0);
        actions.addView(executeButton, actionParams);

        LinearLayout.LayoutParams clearParams =
            new LinearLayout.LayoutParams(0, dp(46), 1f);
        clearParams.setMargins(dp(5), 0, 0, 0);
        actions.addView(clearButton, clearParams);

        root.addView(actions, matchWrap());

        status = new TextView(this);
        status.setText("Pronto • " + tabs.activeName());
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

        renderTabs();
        return root;
    }

    private void renderTabs() {
        tabButtons.removeAllViews();

        for (int i = 0; i < tabs.size(); i++) {
            final int index = i;
            boolean active = i == tabs.activeIndex();
            Button tab = makeTabButton(tabs.nameAt(i), active);
            tab.setOnClickListener(v -> switchTab(index));

            LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(38));
            params.setMargins(0, 0, dp(6), 0);
            tabButtons.addView(tab, params);
        }

        Button add = makeTabButton("+", false);
        add.setMinWidth(dp(48));
        add.setOnClickListener(v -> addTab());
        tabButtons.addView(add, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            dp(38)
        ));
    }

    private void switchTab(int index) {
        if (index == tabs.activeIndex()) {
            return;
        }

        tabs.updateActiveContent(editor.getText().toString());
        tabs.activate(index);
        editor.setText(tabs.activeContent());
        editor.setSelection(editor.length());
        status.setText("Pronto • " + tabs.activeName());
        renderTabs();
    }

    private void addTab() {
        tabs.updateActiveContent(editor.getText().toString());
        String name = tabs.addTab();
        editor.setText("");
        status.setText("Nova aba • " + name);
        renderTabs();
    }

    private void clearActiveTab() {
        editor.setText("");
        tabs.updateActiveContent("");
        console.setText("");
        status.setText("Editor limpo • " + tabs.activeName());
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
        tabs.updateActiveContent(editor == null ? "" : editor.getText().toString());
        runtimeExecutor.shutdownNow();
        super.onDestroy();
    }
}
