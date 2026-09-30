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
 * Private read-only viewer for immutable AI task contracts.
 */
public final class LaboratoryAiTaskContractsActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView feedback;
    private LinearLayout entries;
    private LaboratoryAiTaskContractStore store;

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

        TextView title = text("CONTRATOS DA IA • GOAL LOCK", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Somente leitura. Cada contrato trava objetivo, modo, ferramentas "
                + "e orçamento antes da sessão. Reivindicar um contrato é de uso único.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando contratos…", 14, MUTED, false);
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
        store = new LaboratoryAiTaskContractStore(getFilesDir(), projectId);
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
                List<LaboratoryAiTaskContractStore.Contract> contracts = store.list();
                runOnUiThread(() -> render(contracts));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao ler contratos: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryAiTaskContractStore.Contract> contracts) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(contracts.size() + " contrato(s) neste projeto");

        if (contracts.isEmpty()) {
            entries.addView(text(
                "Nenhum Goal Lock foi criado ainda.",
                14, MUTED, false), matchWrap());
            return;
        }

        for (LaboratoryAiTaskContractStore.Contract contract : contracts) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            String status = contract.resultRecorded
                ? "RESULTADO REGISTRADO"
                : contract.claimed
                    ? "REIVINDICADO • SEM RESULTADO"
                    : "PRONTO • NÃO CONSUMIDO";

            TextView details = text(
                contract.mode.name() + " • " + status
                    + "\nContrato: " + contract.contractId
                    + "\nCriado: " + time(contract.createdAtEpochMs)
                    + "\nObjetivo SHA-256: " + contract.goalSha256
                    + "\nFerramentas: " + contract.allowedToolIds
                    + "\nChamadas: " + contract.maxInvocations
                    + " • Entrada: " + contract.maxTotalInputBytes + " bytes"
                    + "\nTempo máximo: " + contract.maxSessionMs + " ms",
                13, FG, true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            Button goal = button("VER OBJETIVO EXATO");
            goal.setOnClickListener(v -> showGoal(contract));
            LinearLayout.LayoutParams goalParams = matchWrap();
            goalParams.setMargins(0, dp(8), 0, 0);
            card.addView(goal, goalParams);

            if (contract.resultRecorded) {
                Button result = button("VER RESULTADO DA ADMISSÃO");
                result.setOnClickListener(v -> showResult(contract));
                LinearLayout.LayoutParams resultParams = matchWrap();
                resultParams.setMargins(0, dp(8), 0, 0);
                card.addView(result, resultParams);
            }

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }
    }

    private void showGoal(LaboratoryAiTaskContractStore.Contract contract) {
        TextView view = text(contract.goalText, 14, FG, false);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextIsSelectable(true);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);

        new AlertDialog.Builder(this)
            .setTitle("Objetivo travado • " + contract.mode.name())
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private void showResult(LaboratoryAiTaskContractStore.Contract contract) {
        io.execute(() -> {
            try {
                LaboratoryAiTaskContractStore.Result result =
                    store.readResult(contract.contractId);
                String details = "Status: " + result.status
                    + "\nSessão: "
                    + (result.sessionId.isEmpty() ? "nenhuma" : result.sessionId)
                    + "\nMotivo: "
                    + (result.reason.isEmpty() ? "—" : result.reason)
                    + "\nRegistrado: " + time(result.recordedAtEpochMs);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    TextView view = text(details, 13, FG, false);
                    view.setTypeface(Typeface.MONOSPACE);
                    view.setTextIsSelectable(true);
                    view.setPadding(dp(14), dp(12), dp(14), dp(12));
                    new AlertDialog.Builder(this)
                        .setTitle("Admissão do contrato")
                        .setView(view)
                        .setPositiveButton("FECHAR", null)
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Resultado indisponível: " + error.getMessage());
                });
            }
        });
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
