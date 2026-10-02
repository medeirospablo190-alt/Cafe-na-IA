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
 * Host-only, read-only view of deterministic diagnostics for AI sessions and
 * local planner executions.
 */
public final class LaboratoryAiDiagnosticsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiDiagnosticStore store;
    private LaboratoryAiExecutionHistoryStore executionStore;

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
            "Leitura determinística e somente leitura. O diagnóstico observa "
                + "sessões e o planejador local, mas não controla IAs, não "
                + "executa ferramentas, não consome Goal Lock e não aplica "
                + "correções automaticamente.",
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
            store = new LaboratoryAiDiagnosticStore(
                getFilesDir(), projectId);
            executionStore = new LaboratoryAiExecutionHistoryStore(
                getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText(
                "Não foi possível abrir os diagnósticos: "
                    + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            List<LaboratoryAiDiagnosticStore.Report> reports;
            List<LaboratoryAiExecutionHistoryStore.Summary> executions;
            String sessionProblem = null;
            String plannerProblem = null;

            try {
                reports = store.list();
            } catch (Exception error) {
                reports = Collections.emptyList();
                sessionProblem = error.getMessage();
            }

            try {
                executions = executionStore.list();
            } catch (Exception error) {
                executions = Collections.emptyList();
                plannerProblem = error.getMessage();
            }

            final List<LaboratoryAiDiagnosticStore.Report> sessionResult =
                reports;
            final List<LaboratoryAiExecutionHistoryStore.Summary>
                plannerResult = executions;
            final String sessionFailure = sessionProblem;
            final String plannerFailure = plannerProblem;

            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();

                feedback.setText(
                    sessionResult.size() + " sessão(ões) diagnosticada(s) • "
                        + plannerResult.size()
                        + " execução(ões) do planejador registrada(s)");

                addSectionTitle("SESSÕES / FERRAMENTAS");
                if (sessionFailure != null) {
                    entries.addView(text(
                        "Falha na leitura das sessões: " + sessionFailure,
                        13, MUTED, false), matchWrap());
                } else if (sessionResult.isEmpty()) {
                    entries.addView(text(
                        "Ainda não há diagnósticos de sessões.",
                        14, MUTED, false), matchWrap());
                } else {
                    for (LaboratoryAiDiagnosticStore.Report report
                            : sessionResult) {
                        addSessionButton(report);
                    }
                }

                addSectionTitle("PLANEJADOR LOCAL");
                if (plannerFailure != null) {
                    entries.addView(text(
                        "Falha na leitura do planejador: " + plannerFailure,
                        13, MUTED, false), matchWrap());
                } else if (plannerResult.isEmpty()) {
                    entries.addView(text(
                        "Ainda não há execuções terminais do planejador "
                            + "registradas neste projeto.",
                        14, MUTED, false), matchWrap());
                } else {
                    for (LaboratoryAiExecutionHistoryStore.Summary summary
                            : plannerResult) {
                        addPlannerButton(summary);
                    }
                }
            });
        });
    }

    private void addSectionTitle(String label) {
        TextView title = text(label, 14, FG, true);
        title.setPadding(0, dp(16), 0, dp(4));
        entries.addView(title, matchWrap());
    }

    private void addSessionButton(
            LaboratoryAiDiagnosticStore.Report report) {
        Button button = button(
            report.severity + " • " + report.state
                + "\n" + time(report.analyzedAtEpochMs)
                + "  |  " + report.failedInvocations
                + " falha(s) em " + report.invocationResults
                + " resultado(s)");
        button.setAllCaps(false);
        button.setGravity(android.view.Gravity.START
            | android.view.Gravity.CENTER_VERTICAL);
        button.setOnClickListener(v -> showSession(report));
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, 0);
        entries.addView(button, params);
    }

    private void addPlannerButton(
            LaboratoryAiExecutionHistoryStore.Summary summary) {
        LaboratoryAiPlannerExecutionDiagnostic.Result diagnosis =
            LaboratoryAiPlannerExecutionDiagnostic.analyze(summary);

        Button button = button(
            diagnosis.code.name()
                + " • " + summary.state
                + "\n" + time(summary.startedAtEpochMs)
                + "  |  " + phaseLabel(summary.phase)
                + "  |  " + elapsed(summary.elapsedMs)
                + "  |  " + summary.eventCount + " evento(s)");
        button.setAllCaps(false);
        button.setGravity(android.view.Gravity.START
            | android.view.Gravity.CENTER_VERTICAL);
        button.setOnClickListener(v -> showPlanner(summary));
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, 0);
        entries.addView(button, params);
    }

    private void showSession(
            LaboratoryAiDiagnosticStore.Report report) {
        String details = "Sessão: " + report.sessionId
            + "\nSeveridade: " + report.severity
            + "\nEstado: " + report.state
            + "\nMotivo terminal: "
            + (report.terminalReason.isEmpty() ? "—" : report.terminalReason)
            + "\nAnalisado: " + time(report.analyzedAtEpochMs)
            + "\nEventos: " + report.eventCount
            + "\nResultados de ferramentas: " + report.invocationResults
            + "\nFalhas: " + report.failedInvocations
            + "\nCancelamentos de invocação: "
            + report.cancelledInvocations
            + "\nPausas: " + report.pauseCount
            + "\nUso do orçamento de chamadas: "
            + report.invocationUsePercent + "%"
            + "\nUso do orçamento de entrada: "
            + report.inputUsePercent + "%"
            + "\nSinais/recomendações: " + report.recommendationCodes
            + "\n\nNenhuma correção é aplicada automaticamente.";

        showTextDialog(
            "Diagnóstico da IA • somente leitura",
            details);
    }

    private void showPlanner(
            LaboratoryAiExecutionHistoryStore.Summary summary) {
        feedback.setText("Lendo linha do tempo do planejador…");
        io.execute(() -> {
            List<LaboratoryAiExecutionHistoryStore.Event> events;
            String failure = null;
            try {
                events = executionStore.readEvents(summary.executionId);
            } catch (Exception error) {
                events = Collections.emptyList();
                failure = error.getMessage();
            }

            final List<LaboratoryAiExecutionHistoryStore.Event> result =
                events;
            final String problem = failure;
            runOnUiThread(() -> {
                if (!alive()) return;
                feedback.setText(
                    "Linha do tempo carregada • " + result.size()
                        + " evento(s)");

                if (problem != null) {
                    showTextDialog(
                        "Diagnóstico do planejador",
                        "Não foi possível ler a linha do tempo: "
                            + problem);
                    return;
                }

                LaboratoryAiPlannerExecutionDiagnostic.Result diagnosis =
                    LaboratoryAiPlannerExecutionDiagnostic.analyze(summary);
                StringBuilder details = new StringBuilder();
                details.append("Execução: ")
                    .append(summary.executionId)
                    .append("\nContrato: ")
                    .append(summary.contractId)
                    .append("\nEstado: ")
                    .append(summary.state)
                    .append("\nÚltima fase: ")
                    .append(phaseLabel(summary.phase))
                    .append("\nDiagnóstico: ")
                    .append(diagnosis.code.name())
                    .append("\nExplicação: ")
                    .append(diagnosis.explanation)
                    .append("\nPróxima verificação: ")
                    .append(diagnosis.nextCheck)
                    .append("\nInício: ")
                    .append(time(summary.startedAtEpochMs))
                    .append("\nAtualização final: ")
                    .append(time(summary.updatedAtEpochMs))
                    .append("\nDuração: ")
                    .append(elapsed(summary.elapsedMs))
                    .append("\nTentativa: ")
                    .append(summary.attempt)
                    .append("/")
                    .append(summary.maxAttempts)
                    .append("\nEventos persistidos: ")
                    .append(summary.eventCount)
                    .append("\nMotivo terminal: ")
                    .append(summary.terminalReason.isEmpty()
                        ? "—"
                        : summary.terminalReason)
                    .append("\n\nTELEMETRIA")
                    .append("\nContexto: ")
                    .append(summary.contextSetupMs)
                    .append(" ms")
                    .append("\nPrompt: ")
                    .append(summary.promptTokensProcessed)
                    .append("/")
                    .append(summary.promptTokens)
                    .append(" tokens • ")
                    .append(summary.promptEvalMs)
                    .append(" ms")
                    .append("\nGeração: ")
                    .append(summary.generatedTokens)
                    .append("/")
                    .append(summary.maxGeneratedTokens)
                    .append(" tokens • ")
                    .append(summary.tokenGenerationMs)
                    .append(" ms")
                    .append("\nLimite de geração: ")
                    .append(summary.generationTimeLimitMs)
                    .append(" ms")
                    .append("\n\nLINHA DO TEMPO");

                for (LaboratoryAiExecutionHistoryStore.Event event : result) {
                    details.append("\n#")
                        .append(event.sequence)
                        .append(" • +")
                        .append(elapsed(event.elapsedMs))
                        .append(" • ")
                        .append(event.state)
                        .append(" • ")
                        .append(phaseLabel(event.phase));
                    if (!event.detail.isEmpty()) {
                        details.append("\n  ").append(event.detail);
                    }
                    if (!event.terminalReason.isEmpty()) {
                        details.append("\n  Motivo: ")
                            .append(event.terminalReason);
                    }
                }

                details.append(
                    "\n\nEste diagnóstico é somente leitura. "
                        + "Ele não reinicia o planejador, não altera limites "
                        + "e não executa ferramentas.");

                showTextDialog(
                    "Diagnóstico do planejador • somente leitura",
                    details.toString());
            });
        });
    }

    private void showTextDialog(String title, String details) {
        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);
        new AlertDialog.Builder(this)
            .setTitle(title)
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

    private TextView text(
            String value,
            int size,
            int color,
            boolean bold) {
        TextView result = new TextView(this);
        result.setText(value);
        result.setTextSize(size);
        result.setTextColor(color);
        if (bold) {
            result.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        }
        return result;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(
            value * getResources().getDisplayMetrics().density);
    }

    private boolean alive() {
        return !isFinishing() && !isDestroyed();
    }

    private static String time(long epochMs) {
        if (epochMs <= 0) return "Data indisponível";
        return DateFormat.getDateTimeInstance(
            DateFormat.SHORT,
            DateFormat.SHORT,
            new Locale("pt", "BR"))
            .format(new Date(epochMs));
    }

    private static String phaseLabel(
            LaboratoryAiExecutionStatus.Phase phase) {
        if (phase == null) return "Etapa desconhecida";
        switch (phase) {
            case PREPARING:
                return "Preparando";
            case MODEL_ADMISSION:
                return "Admissão do modelo";
            case PREFLIGHT:
                return "Preflight do dispositivo";
            case MODEL_OPEN:
                return "Abertura do modelo";
            case RUNTIME_METADATA:
                return "Metadados do runtime";
            case PLANNING:
                return "Montagem do plano";
            case MODEL_CONTEXT:
                return "Contexto do modelo";
            case MODEL_PROMPT:
                return "Processamento do prompt";
            case MODEL_TOKENS:
                return "Geração de tokens";
            case VALIDATING:
                return "Validação determinística";
            case COMPLETED:
                return "Concluído";
            default:
                return phase.name();
        }
    }

    private static String elapsed(long elapsedMs) {
        long safe = Math.max(0L, elapsedMs);
        if (safe < 1000L) return safe + " ms";
        long seconds = safe / 1000L;
        long minutes = seconds / 60L;
        long remainder = seconds % 60L;
        if (minutes == 0L) return remainder + " s";
        return minutes + " min " + remainder + " s";
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null && executionStore != null) {
            refresh();
        }
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
