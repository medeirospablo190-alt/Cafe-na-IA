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
 * Read-only team-level diagnostics. It has no session or tool handles.
 */
public final class LaboratoryAiTeamDiagnosticsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiTeamDiagnosticStore store;
    private String projectId;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(16), dp(16), dp(16));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("DIAGNÓSTICO • EQUIPE DE IAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Análise agregada por membro da equipe. Usa apenas diagnósticos "
                + "sanitizados e vínculos de sessão; não lê prompt, objetivo, "
                + "tool_input, retorno ou conversa.",
            13, MUTED, false), matchWrap());

        feedback = text("Atualizando diagnóstico da equipe…", 14, MUTED, false);
        feedback.setPadding(0, dp(14), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        projectId = getSharedPreferences(
            "cafeina_workspace", MODE_PRIVATE).getString("project_id", "");
        store = new LaboratoryAiTeamDiagnosticStore(getFilesDir(), projectId);
        refresh(true);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null) refresh(true);
    }

    private void refresh(boolean analyze) {
        io.execute(() -> {
            List<LaboratoryAiTeamDiagnosticStore.Report> reports;
            String problem = null;
            try {
                if (analyze) {
                    LaboratoryAiTeamDiagnostics.analyzeAllNow(
                        getApplicationContext(), projectId);
                }
                reports = store.list();
            } catch (Exception error) {
                reports = Collections.emptyList();
                problem = error.getMessage();
            }

            final List<LaboratoryAiTeamDiagnosticStore.Report> result = reports;
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha no diagnóstico da equipe: " + failure);
                    return;
                }
                feedback.setText(result.size()
                    + " membro(s) • somente leitura • nenhuma correção automática");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Ainda não há membros registrados na equipe de IA.",
                        14, MUTED, false), matchWrap());
                    return;
                }

                for (LaboratoryAiTeamDiagnosticStore.Report report : result) {
                    String latest = report.latestSeverity.isEmpty()
                        ? "SEM SESSÕES" : report.latestSeverity;
                    Button item = button(
                        report.displayName + " • " + report.role
                            + "\n" + latest + " • tendência " + report.trend
                            + " • " + report.sessionCount + " sessão(ões)"
                            + "\n" + report.failureSessions
                            + " sessão(ões) com falha • "
                            + report.failedInvocations + " falha(s) de ferramenta");
                    item.setAllCaps(false);
                    item.setGravity(android.view.Gravity.START
                        | android.view.Gravity.CENTER_VERTICAL);
                    item.setOnClickListener(v -> show(report));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    entries.addView(item, params);
                }
            });
        });
    }

    private void show(LaboratoryAiTeamDiagnosticStore.Report report) {
        String details =
            "IA: " + report.displayName
            + "\nID: " + report.agentId
            + "\nPapel: " + report.role
            + "\nAnalisado: " + time(report.analyzedAtEpochMs)
            + "\nSessões diagnosticadas: " + report.sessionCount
            + "\nSaudáveis: " + report.healthySessions
            + "\nAtenção: " + report.attentionSessions
            + "\nFalhas: " + report.failureSessions
            + "\nFalhas de ferramenta: " + report.failedInvocations
            + "\nCancelamentos de invocação: " + report.cancelledInvocations
            + "\nPausas: " + report.pauseCount
            + "\nMédia de orçamento de chamadas: "
            + report.averageInvocationUsePercent + "%"
            + "\nMédia de orçamento de entrada: "
            + report.averageInputUsePercent + "%"
            + "\nTendência: " + report.trend
            + "\nÚltima sessão: "
            + (report.latestSessionId.isEmpty() ? "—" : report.latestSessionId)
            + "\nÚltima severidade: "
            + (report.latestSeverity.isEmpty() ? "—" : report.latestSeverity)
            + "\nSinais recorrentes: " + report.recurrentSignals
            + "\nRecomendações: " + report.recommendationCodes
            + "\n\nA IA de diagnóstico não aplica mudanças.";

        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);

        new AlertDialog.Builder(this)
            .setTitle("Diagnóstico do membro • somente leitura")
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
            DateFormat.SHORT, DateFormat.SHORT,
            new Locale("pt", "BR")).format(new Date(epochMs));
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
