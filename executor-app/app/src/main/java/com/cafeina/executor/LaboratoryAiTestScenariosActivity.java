package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.text.DateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private read-only scenario catalog viewer.
 */
public final class LaboratoryAiTestScenariosActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView feedback;
    private LinearLayout entries;
    private LaboratoryAiTestScenarioStore store;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("IA DE TESTE • CENÁRIOS", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Catálogo imutável de planos determinísticos. Esta tela apenas "
                + "inspeciona cenários; executar exige Goal Lock compatível.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando cenários…", 14, MUTED, false);
        feedback.setPadding(0, dp(12), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        String projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        store = new LaboratoryAiTestScenarioStore(getFilesDir(), projectId);
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null) refresh();
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryAiTestScenarioStore.Scenario> scenarios =
                    store.list();
                runOnUiThread(() -> render(scenarios));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao ler cenários: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryAiTestScenarioStore.Scenario> scenarios) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(scenarios.size() + " cenário(s) imutável(is)");

        if (scenarios.isEmpty()) {
            entries.addView(text(
                "Nenhum cenário da IA de teste foi criado ainda.",
                14, MUTED, false), matchWrap());
            return;
        }

        for (LaboratoryAiTestScenarioStore.Scenario scenario : scenarios) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            TextView details = text(
                scenario.name
                    + "\nID: " + scenario.scenarioId
                    + "\nCriado: " + time(scenario.createdAtEpochMs)
                    + "\nSHA-256: " + scenario.scenarioSha256
                    + "\nPassos: " + scenario.stepCount
                    + " • Stop on failure: "
                    + (scenario.stopOnFailure ? "SIM" : "NÃO"),
                13, FG, true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            Button inspect = button("INSPECIONAR PASSOS");
            inspect.setOnClickListener(v -> showScenario(scenario));
            LinearLayout.LayoutParams inspectParams = matchWrap();
            inspectParams.setMargins(0, dp(8), 0, 0);
            card.addView(inspect, inspectParams);

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }
    }

    private void showScenario(LaboratoryAiTestScenarioStore.Scenario scenario) {
        StringBuilder body = new StringBuilder()
            .append("Cenário: ").append(scenario.name)
            .append("\nID: ").append(scenario.scenarioId)
            .append("\nSHA-256: ").append(scenario.scenarioSha256)
            .append("\nStop on failure: ")
            .append(scenario.stopOnFailure ? "SIM" : "NÃO");

        for (LaboratoryAiTestAgent.Step step : scenario.plan.steps) {
            body.append("\n\nPASSO • ").append(step.name)
                .append("\nFerramenta: ").append(step.toolId)
                .append("\nEntrada:")
                .append("\n").append(step.input)
                .append("\nRetorno esperado:")
                .append("\n").append(step.expectedFirstReturn);
        }

        TextView view = text(body.toString(), 13, FG, false);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextIsSelectable(true);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);

        new AlertDialog.Builder(this)
            .setTitle("Cenário • somente leitura")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(14);
        button.setBackgroundTintList(ColorStateList.valueOf(ACCENT));
        return button;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static String time(long epochMs) {
        if (epochMs <= 0) return "Data indisponível";
        return DateFormat.getDateTimeInstance(
            DateFormat.SHORT, DateFormat.SHORT,
            new Locale("pt", "BR")).format(new Date(epochMs));
    }

    private boolean alive() {
        return !isFinishing() && !isDestroyed();
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
