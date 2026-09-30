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
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Host-only, read-only view of deterministic diagnostics for all AI sessions.
 */
public final class LaboratoryAiDiagnosticsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);
    private static final int ACCENT = Color.rgb(82, 118, 255);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiDiagnosticStore store;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(16), dp(16), dp(16));
        root.setBackgroundColor(BG);
        setContentView(root);

        root.addView(text("DIAGNÓSTICO DAS IAS", 22, FG, true), matchWrap());
        root.addView(text(
            "Leitura determinística das sessões. Não controla IAs, não executa "
                + "ferramentas e não persiste entrada, retorno, stdout ou erro bruto.",
            13, MUTED, false), matchWrap());

        feedback = text("Carregando diagnósticos…", 14, MUTED, false);
        feedback.setPadding(0, dp(14), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        String projectId = getSharedPreferences(
            "cafeina_workspace", MODE_PRIVATE).getString("project_id", "");
        try {
            store = new LaboratoryAiDiagnosticStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText(
                "Não foi possível abrir os diagnósticos: " + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            List<LaboratoryAiDiagnosticStore.Report> reports;
            String problem = null;
            try {
                reports = store.list();
            } catch (Exception error) {
                reports = Collections.emptyList();
                problem = error.getMessage();
            }
            final List<LaboratoryAiDiagnosticStore.Report> result = reports;
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha na leitura: " + failure);
                    return;
                }
                feedback.setText(result.size()
                    + " diagnóstico(s) • último estado por sessão • somente leitura");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Ainda não há diagnósticos. Eles são atualizados conforme "
                            + "as sessões de IA executam e encerram.",
                        14, MUTED, false), matchWrap());
                    return;
                }
                for (LaboratoryAiDiagnosticStore.Report report : result) {
                    Button button = button(
                        report.severity + " • " + report.state
                            + "\n" + time(report.analyzedAtEpochMs)
                            + "  |  " + report.failedInvocations
                            + " falha(s) em " + report.invocationResults
                            + " resultado(s)");
                    button.setAllCaps(false);
                    button.setGravity(android.view.Gravity.START
                        | android.view.Gravity.CENTER_VERTICAL);
                    button.setOnClickListener(v -> show(report));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    entries.addView(button, params);
                }
            });
        });
    }

    private void show(LaboratoryAiDiagnosticStore.Report report) {
        String details = "Sessão: " + report.sessionId
            + "\nSeveridade: " + report.severity
            + "\nEstado: " + report.state
            + "\nMotivo terminal: "
            + (report.terminalReason.isEmpty() ? "—" : report.terminalReason)
            + "\nAnalisado: " + time(report.analyzedAtEpochMs)
            + "\nEventos: " + report.eventCount
            + "\nResultados de ferramentas: " + report.invocationResults
            + "\nFalhas: " + report.failedInvocations
            + "\nCancelamentos de invocação: " + report.cancelledInvocations
            + "\nPausas: " + report.pauseCount
            + "\nUso do orçamento de chamadas: "
            + report.invocationUsePercent + "%"
            + "\nUso do orçamento de entrada: "
            + report.inputUsePercent + "%"
            + "\nSinais/recomendações: " + report.recommendationCodes
            + "\n\nNenhuma correção é aplicada automaticamente.";

        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);
        new AlertDialog.Builder(this)
            .setTitle("Diagnóstico da IA • somente leitura")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private Button button(String label) {
        Button result = new Button(this);
        result.setText(label);
        result.setTextSize(14);
        result.setTextColor(FG);
        result.setBackgroundTintList(ColorStateList.valueOf(PANEL));
        return result;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView result = new TextView(this);
        result.setText(value);
        result.setTextSize(size);
        result.setTextColor(color);
        if (bold) result.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return result;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private boolean alive() {
        return !isFinishing() && !isDestroyed();
    }

    private static String time(long epochMs) {
        if (epochMs <= 0) return "Data indisponível";
        return DateFormat.getDateTimeInstance(
            DateFormat.SHORT, DateFormat.SHORT, new Locale("pt", "BR"))
            .format(new Date(epochMs));
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null) refresh();
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
