package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Controlled UI for proving the first real local-model planner path.
 *
 * It may load the selected GGUF and ask for a plan. A validated plan remains
 * non-executable until the user explicitly prepares an immutable scenario and
 * confirms a second, separate TestAgent execution gate.
 */
public final class LaboratoryAiLocalPlannerActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private static final String MODEL_PREFS = "cafeina_ai_local_model";
    private static final String ACTIVE_MODEL = "active_model_filename";

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService historyWorker =
        Executors.newSingleThreadExecutor();

    private String projectId;
    private LaboratoryAiTaskContractStore contracts;
    private LaboratoryAiExecutionHistoryStore executionHistory;
    private TextView feedback;
    private TextView modelStatus;
    private LinearLayout entries;
    private Button cancelPlannerButton;
    private volatile LaboratoryAiLocalPlannerProbe.Cancellation
        activePlanningCancellation;
    private volatile boolean busy;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        projectId = getSharedPreferences(
            "cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        contracts = new LaboratoryAiTaskContractStore(
            getFilesDir(), projectId);
        executionHistory = new LaboratoryAiExecutionHistoryStore(
            getFilesDir(), projectId);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR", PANEL);
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text(
            "IA LOCAL • PLANEJADOR",
            20,
            FG,
            true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Teste controlado: o modelo local recebe um Goal Lock já criado, "
                + "propõe JSON e o contrato determinístico valida. Nenhuma "
                + "ferramenta é executada nesta tela.",
            14,
            MUTED,
            false), matchWrap());

        modelStatus = text("", 13, MUTED, false);
        modelStatus.setPadding(0, dp(12), 0, dp(4));
        root.addView(modelStatus, matchWrap());

        feedback = text("Carregando contratos…", 13, MUTED, false);
        feedback.setPadding(0, dp(4), 0, dp(8));
        root.addView(feedback, matchWrap());

        Button historyButton = button(
            "HISTÓRICO DO PLANEJADOR",
            PANEL);
        historyButton.setOnClickListener(v ->
            showExecutionHistory());
        LinearLayout.LayoutParams historyParams = matchWrap();
        historyParams.setMargins(0, 0, 0, dp(8));
        root.addView(historyButton, historyParams);

        cancelPlannerButton = button(
            "CANCELAR PLANEJAMENTO",
            PANEL);
        cancelPlannerButton.setVisibility(View.GONE);
        cancelPlannerButton.setOnClickListener(v ->
            cancelActivePlanning());
        LinearLayout.LayoutParams cancelParams = matchWrap();
        cancelParams.setMargins(0, 0, 0, dp(8));
        root.addView(cancelPlannerButton, cancelParams);

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (contracts != null && !busy) refresh();
    }

    private void refresh() {
        final String selected = selectedModelFileName();
        modelStatus.setText(selected.isEmpty()
            ? "Modelo ativo: nenhum. Selecione um GGUF na aba IA."
            : "Modelo ativo: " + shortName(selected));

        worker.execute(() -> {
            try {
                List<LaboratoryAiTaskContractStore.Contract> all =
                    contracts.list();
                List<LaboratoryAiTaskContractStore.Contract> unused =
                    new ArrayList<>();
                for (LaboratoryAiTaskContractStore.Contract contract : all) {
                    if (!contract.claimed && !contract.resultRecorded) {
                        unused.add(contract);
                    }
                }
                runOnUiThread(() -> render(unused, selected));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText(
                        "Falha ao ler Goal Locks: "
                            + String.valueOf(error.getMessage()));
                });
            }
        });
    }

    private void render(
            List<LaboratoryAiTaskContractStore.Contract> unused,
            String selectedModel) {
        if (!alive()) return;

        entries.removeAllViews();
        feedback.setText(
            unused.size()
                + " Goal Lock(s) disponível(is) • planejamento não consome o contrato");

        if (unused.isEmpty()) {
            entries.addView(text(
                "Ainda não existe um Goal Lock não consumido neste projeto. "
                    + "O planejador só trabalha em cima de contratos já "
                    + "criados pelo fluxo do laboratório.",
                14,
                MUTED,
                false), matchWrap());
            return;
        }

        for (LaboratoryAiTaskContractStore.Contract contract : unused) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(
                ColorStateList.valueOf(PANEL));

            TextView details = text(
                contract.mode.name()
                    + " • NÃO CONSUMIDO"
                    + "\nContrato: " + contract.contractId
                    + "\nObjetivo SHA-256: " + contract.goalSha256
                    + "\nFerramentas: " + contract.allowedToolIds
                    + "\nChamadas: " + contract.maxInvocations
                    + " • Entrada: "
                    + contract.maxTotalInputBytes + " bytes"
                    + "\nTempo: " + contract.maxSessionMs + " ms",
                13,
                FG,
                true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            Button plan = button(
                busy
                    ? "PLANEJADOR OCUPADO…"
                    : "GERAR PLANO • NÃO EXECUTAR",
                ACCENT);
            plan.setEnabled(
                !busy && !selectedModel.isEmpty());
            plan.setOnClickListener(v ->
                planContract(contract.contractId));

            LinearLayout.LayoutParams planParams = matchWrap();
            planParams.setMargins(0, dp(8), 0, 0);
            card.addView(plan, planParams);

            if (selectedModel.isEmpty()) {
                TextView hint = text(
                    "Selecione um modelo ativo na aba IA antes do teste.",
                    12,
                    MUTED,
                    false);
                hint.setPadding(0, dp(4), 0, 0);
                card.addView(hint, matchWrap());
            }

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }
    }

    private void planContract(String contractId) {
        if (busy) return;

        final String selected = selectedModelFileName();
        if (selected.isEmpty()) {
            feedback.setText(
                "Nenhum modelo ativo. Volte à aba IA e selecione um GGUF.");
            return;
        }

        final LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            new LaboratoryAiLocalPlannerProbe.Cancellation();
        activePlanningCancellation = cancellation;

        final LaboratoryAiExecutionStatus.Tracker executionStatus =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                snapshot -> runOnUiThread(() ->
                    renderExecutionStatus(snapshot)));

        busy = true;
        cancelPlannerButton.setEnabled(true);
        cancelPlannerButton.setVisibility(View.VISIBLE);
        refreshBusyState();

        worker.execute(() -> {
            try {
                LaboratoryAiLocalModelCatalog.Model model =
                    LaboratoryAiLocalModelCatalog.resolve(
                        getFilesDir(), selected);

                LaboratoryAiLocalPlannerProbe.Result result =
                    LaboratoryAiLocalPlannerProbe.plan(
                        this,
                        projectId,
                        contractId,
                        model.modelFile,
                        cancellation,
                        executionStatus);

                LaboratoryAiTaskContractStore.Contract after =
                    contracts.read(contractId);
                if (after.claimed || after.resultRecorded) {
                    throw new IllegalStateException(
                        "Goal Lock foi alterado durante o planejamento");
                }

                persistExecutionHistory(executionStatus);
                runOnUiThread(() -> {
                    clearPlanningCancellation(cancellation);
                    showPlannerResult(contractId, result);
                });
            } catch (Exception error) {
                LaboratoryAiExecutionStatus.Snapshot terminal =
                    executionStatus.snapshot();
                if (!terminal.terminal()) {
                    if (cancellation.isCancelled()) {
                        executionStatus.cancel(
                            "Planejamento cancelado pelo usuário");
                    } else {
                        executionStatus.fail(
                            String.valueOf(error.getMessage()));
                    }
                }
                persistExecutionHistory(executionStatus);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    boolean cancelled = cancellation.isCancelled();
                    clearPlanningCancellation(cancellation);
                    busy = false;
                    LaboratoryAiExecutionStatus.Snapshot snapshot =
                        executionStatus.snapshot();
                    feedback.setText(statusLine(snapshot));
                    new AlertDialog.Builder(this)
                        .setTitle(
                            cancelled
                                ? "Planejamento cancelado"
                                : "Plano não produzido")
                        .setMessage(
                            "Nenhuma ferramenta foi executada e o Goal Lock "
                                + "não foi consumido.\n\n"
                                + diagnosticSummary(snapshot))
                        .setPositiveButton(
                            "OK",
                            (dialog, which) -> refresh())
                        .setOnCancelListener(dialog -> refresh())
                        .show();
                });
            }
        });
    }

    private void showPlannerResult(
            String contractId,
            LaboratoryAiLocalPlannerProbe.Result result) {
        if (!alive()) return;

        busy = false;
        LaboratoryAiLlmTestPlanner.Result planner = result.planner;
        StringBuilder body = new StringBuilder()
            .append("Contrato: ").append(contractId)
            .append("\nModelo: ").append(result.modelFileName)
            .append("\nRuntime: ").append(result.runtimeVersion)
            .append("\nDescrição: ").append(result.modelDescription)
            .append("\nPreflight: ").append(result.preflight.status)
            .append("\nSinais: ").append(result.preflight.signalCodes)
            .append("\nTentativas: ").append(planner.attempts)
            .append("\nGoal Lock: NÃO CONSUMIDO");

        String title;
        if (planner.accepted && planner.plan != null) {
            title = "Plano validado";
            body.append("\n\nRESULTADO: ACEITO")
                .append("\nStop on failure: ")
                .append(planner.plan.stopOnFailure ? "SIM" : "NÃO")
                .append("\nPassos: ")
                .append(planner.plan.steps.size());

            int index = 1;
            for (LaboratoryAiTestAgent.Step step :
                    planner.plan.steps) {
                body.append("\n\nPASSO ").append(index++)
                    .append(" • ").append(step.name)
                    .append("\nFerramenta: ").append(step.toolId)
                    .append("\nEntrada:\n").append(step.input)
                    .append("\nRetorno esperado:\n")
                    .append(step.expectedFirstReturn);
            }
        } else {
            title = "Plano rejeitado";
            body.append("\n\nRESULTADO: REJEITADO");
            for (LaboratoryAiTestPlanContract.Issue issue :
                    planner.issues) {
                body.append("\n• ")
                    .append(issue.code)
                    .append(" • passo ")
                    .append(issue.stepIndex)
                    .append(" • campo ")
                    .append(issue.field);
            }
            body.append(
                "\n\nO texto bruto rejeitado do modelo não foi persistido.");
        }

        ScrollView scroll = new ScrollView(this);
        TextView details = text(
            body.toString(), 13, FG, false);
        details.setTypeface(Typeface.MONOSPACE);
        details.setTextIsSelectable(true);
        details.setPadding(dp(14), dp(12), dp(14), dp(12));
        details.setGravity(Gravity.START);
        scroll.addView(details);

        AlertDialog.Builder dialog = new AlertDialog.Builder(this)
            .setTitle(title)
            .setView(scroll)
            .setPositiveButton("FECHAR", (ignored, which) -> refresh())
            .setOnCancelListener(ignored -> refresh());

        if (planner.accepted && planner.plan != null) {
            dialog.setNeutralButton(
                "PREPARAR TESTADORA",
                (ignored, which) ->
                    prepareForTestAgent(contractId, planner.plan));
        }
        dialog.show();

        feedback.setText(
            planner.accepted
                ? "Plano aceito • ainda não executado • aguarda gate humano"
                : "Plano rejeitado após "
                    + planner.attempts + " tentativa(s) • não executado");
    }

    private void prepareForTestAgent(
            String contractId,
            LaboratoryAiTestAgent.Plan plan) {
        if (busy) return;
        busy = true;
        feedback.setText(
            "Gravando cenário imutável para revisão…");
        refreshBusyState();

        worker.execute(() -> {
            try {
                LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
                    LaboratoryAiValidatedPlanExecutionGate.prepare(
                        this,
                        projectId,
                        contractId,
                        plan);
                runOnUiThread(() ->
                    confirmPreparedExecution(prepared));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Plano não foi preparado: "
                            + String.valueOf(error.getMessage()));
                    refresh();
                    new AlertDialog.Builder(this)
                        .setTitle("Testadora não preparada")
                        .setMessage(
                            "Nenhuma ferramenta foi executada e o Goal Lock "
                                + "não foi consumido.\n\n"
                                + String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
                        .show();
                });
            }
        });
    }

    private void confirmPreparedExecution(
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared) {
        if (!alive()) return;
        busy = false;

        String details =
            "Contrato: " + prepared.contractId
                + "\nGoal SHA-256: " + prepared.goalSha256
                + "\nCenário: " + prepared.scenarioId
                + "\nCenário SHA-256: " + prepared.scenarioSha256
                + "\nPassos: " + prepared.stepCount
                + "\nStop on failure: "
                + (prepared.stopOnFailure ? "SIM" : "NÃO")
                + "\n\nAté aqui nenhuma ferramenta foi executada e o "
                + "Goal Lock continua não consumido."
                + "\n\nEXECUTAR TESTADORA irá consumir esse Goal Lock "
                + "uma única vez e permitirá somente as ferramentas já "
                + "travadas no contrato.";

        new AlertDialog.Builder(this)
            .setTitle("Gate de execução • Testadora")
            .setMessage(details)
            .setNegativeButton("NÃO EXECUTAR", (dialog, which) -> refresh())
            .setPositiveButton(
                "EXECUTAR TESTADORA",
                (dialog, which) -> executePrepared(prepared))
            .setOnCancelListener(dialog -> refresh())
            .show();

        feedback.setText(
            "Cenário preparado • aguardando confirmação de execução");
    }

    private void executePrepared(
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared) {
        if (busy) return;
        busy = true;
        feedback.setText(
            "Executando Testadora pelo Goal Lock…");
        refreshBusyState();

        worker.execute(() -> {
            try {
                LaboratoryAiValidatedPlanExecutionGate.Execution execution =
                    LaboratoryAiValidatedPlanExecutionGate.executePrepared(
                        this,
                        projectId,
                        prepared);

                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Testadora concluída • " + execution.status);
                    new AlertDialog.Builder(this)
                        .setTitle("Execução da Testadora")
                        .setMessage(
                            "Status: " + execution.status
                                + "\nContrato: " + execution.contractId
                                + "\nCenário: " + execution.scenarioId
                                + "\nCenário SHA-256: "
                                + execution.scenarioSha256
                                + "\nRelatório: " + execution.reportId
                                + "\nSessão: "
                                + (execution.sessionId.isEmpty()
                                    ? "nenhuma"
                                    : execution.sessionId)
                                + "\nGoal Lock reivindicado: "
                                + (execution.goalLockClaimed ? "SIM" : "NÃO")
                                + "\nResultado de admissão persistido: "
                                + (execution.resultRecorded ? "SIM" : "NÃO")
                                + "\n\nA Testadora usou o caminho de "
                                + "admissão one-use. O estado acima foi relido "
                                + "do armazenamento persistente após a execução.")
                        .setPositiveButton(
                            "OK",
                            (dialog, which) -> refresh())
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Execução bloqueada/falhou: "
                            + String.valueOf(error.getMessage()));
                    new AlertDialog.Builder(this)
                        .setTitle("Testadora não executada")
                        .setMessage(
                            "O gate interrompeu a transição ou a execução "
                                + "falhou. Consulte contratos e relatórios para "
                                + "confirmar se o Goal Lock chegou a ser "
                                + "consumido.\n\n"
                                + String.valueOf(error.getMessage()))
                        .setPositiveButton(
                            "OK",
                            (dialog, which) -> refresh())
                        .show();
                });
            }
        });
    }

    private void cancelActivePlanning() {
        LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            activePlanningCancellation;
        if (cancellation == null || cancellation.isCancelled()) {
            return;
        }
        cancellation.cancel();
        if (cancelPlannerButton != null) {
            cancelPlannerButton.setEnabled(false);
            cancelPlannerButton.setText("CANCELANDO…");
        }
        feedback.setText(
            "Cancelamento solicitado ao runtime local…");
    }

    private void clearPlanningCancellation(
            LaboratoryAiLocalPlannerProbe.Cancellation cancellation) {
        if (activePlanningCancellation == cancellation) {
            activePlanningCancellation = null;
        }
        if (cancelPlannerButton != null) {
            cancelPlannerButton.setEnabled(true);
            cancelPlannerButton.setText("CANCELAR PLANEJAMENTO");
            cancelPlannerButton.setVisibility(View.GONE);
        }
    }

    private void persistExecutionHistory(
            LaboratoryAiExecutionStatus.Tracker tracker) {
        if (tracker == null || executionHistory == null) return;
        try {
            executionHistory.saveExecution(tracker.history());
        } catch (Exception ignored) {
            // History is diagnostic only and never controls planner execution.
        }
    }

    private void showExecutionHistory() {
        if (executionHistory == null) return;
        historyWorker.execute(() -> {
            try {
                List<LaboratoryAiExecutionHistoryStore.Summary> summaries =
                    executionHistory.list();
                String body = executionHistoryText(summaries);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    ScrollView scroll = new ScrollView(this);
                    TextView details = text(body, 13, FG, false);
                    details.setTypeface(Typeface.MONOSPACE);
                    details.setTextIsSelectable(true);
                    details.setPadding(
                        dp(14), dp(12), dp(14), dp(12));
                    scroll.addView(details);

                    new AlertDialog.Builder(this)
                        .setTitle("Histórico do planejador")
                        .setView(scroll)
                        .setPositiveButton("FECHAR", null)
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    new AlertDialog.Builder(this)
                        .setTitle("Histórico indisponível")
                        .setMessage(String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
                        .show();
                });
            }
        });
    }

    private static String executionHistoryText(
            List<LaboratoryAiExecutionHistoryStore.Summary> summaries) {
        if (summaries == null || summaries.isEmpty()) {
            return "Nenhuma execução do planejador foi persistida ainda.";
        }

        StringBuilder out = new StringBuilder();
        int limit = Math.min(20, summaries.size());
        for (int i = 0; i < limit; i++) {
            LaboratoryAiExecutionHistoryStore.Summary summary =
                summaries.get(i);
            if (i > 0) out.append("\n\n");
            out.append(summary.state.name())
                .append(" • ")
                .append(summary.phase.name())
                .append("\nExecução: ")
                .append(summary.executionId)
                .append("\nContrato: ")
                .append(summary.contractId)
                .append("\nTempo: ")
                .append(summary.elapsedMs)
                .append(" ms")
                .append("\nEventos: ")
                .append(summary.eventCount);
            if (summary.attempt > 0 && summary.maxAttempts > 0) {
                out.append("\nTentativa: ")
                    .append(summary.attempt)
                    .append("/")
                    .append(summary.maxAttempts);
            }
            if (!summary.terminalReason.isEmpty()) {
                out.append("\nMotivo: ")
                    .append(summary.terminalReason);
            }
        }
        if (summaries.size() > limit) {
            out.append("\n\n… ")
                .append(summaries.size() - limit)
                .append(" execução(ões) anterior(es) omitida(s).");
        }
        return out.toString();
    }

    private void renderExecutionStatus(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (!alive() || snapshot == null) return;
        feedback.setText(statusLine(snapshot));
    }

    private static String statusLine(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (snapshot == null) return "Planejador • status indisponível";
        StringBuilder out = new StringBuilder()
            .append("Planejador • ")
            .append(phaseLabel(snapshot.phase));
        if (snapshot.attempt > 0 && snapshot.maxAttempts > 0) {
            out.append(" • tentativa ")
                .append(snapshot.attempt)
                .append("/")
                .append(snapshot.maxAttempts);
        }
        out.append(" • ").append(formatElapsed(snapshot.elapsedMs));
        if (snapshot.state == LaboratoryAiExecutionStatus.State.FAILED) {
            out.append(" • FALHOU");
        } else if (snapshot.state
                == LaboratoryAiExecutionStatus.State.CANCELLED) {
            out.append(" • CANCELADO");
        } else if (snapshot.state
                == LaboratoryAiExecutionStatus.State.COMPLETED) {
            out.append(" • CONCLUÍDO");
        }
        return out.toString();
    }

    private static String diagnosticSummary(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (snapshot == null) return "Diagnóstico de execução indisponível.";
        StringBuilder out = new StringBuilder()
            .append("Execução: ").append(snapshot.executionId)
            .append("\nContrato: ").append(snapshot.contractId)
            .append("\nEstado: ").append(snapshot.state.name())
            .append("\nFase: ").append(snapshot.phase.name())
            .append("\nTempo decorrido: ")
            .append(snapshot.elapsedMs).append(" ms");
        if (snapshot.attempt > 0 && snapshot.maxAttempts > 0) {
            out.append("\nTentativa: ")
                .append(snapshot.attempt)
                .append("/")
                .append(snapshot.maxAttempts);
        }
        if (!snapshot.detail.isEmpty()) {
            out.append("\nÚltimo status: ").append(snapshot.detail);
        }
        if (!snapshot.terminalReason.isEmpty()) {
            out.append("\nMotivo: ").append(snapshot.terminalReason);
        }
        return out.toString();
    }

    private static String phaseLabel(
            LaboratoryAiExecutionStatus.Phase phase) {
        if (phase == null) return "status desconhecido";
        switch (phase) {
            case PREPARING:
                return "preparando";
            case MODEL_ADMISSION:
                return "validando modelo";
            case PREFLIGHT:
                return "pré-verificação";
            case MODEL_OPEN:
                return "abrindo modelo";
            case RUNTIME_METADATA:
                return "lendo runtime";
            case PLANNING:
                return "gerando proposta";
            case MODEL_CONTEXT:
                return "preparando contexto";
            case MODEL_PROMPT:
                return "processando prompt";
            case MODEL_TOKENS:
                return "gerando tokens";
            case VALIDATING:
                return "validando plano";
            case COMPLETED:
                return "concluído";
            default:
                return phase.name().toLowerCase();
        }
    }

    private static String formatElapsed(long elapsedMs) {
        long seconds = Math.max(0L, elapsedMs) / 1000L;
        long minutes = seconds / 60L;
        long remainder = seconds % 60L;
        if (minutes == 0L) return remainder + " s";
        return minutes + " min " + remainder + " s";
    }

    private void refreshBusyState() {
        for (int i = 0; i < entries.getChildCount(); i++) {
            entries.getChildAt(i).setEnabled(!busy);
        }
    }

    private String selectedModelFileName() {
        return getSharedPreferences(
            MODEL_PREFS, MODE_PRIVATE)
            .getString(ACTIVE_MODEL, "");
    }

    private static String shortName(String value) {
        if (value == null || value.isEmpty()) return "—";
        return value.length() <= 40
            ? value
            : value.substring(0, 37) + "…";
    }

    private Button button(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextColor(FG);
        button.setTextSize(14);
        button.setBackgroundTintList(
            ColorStateList.valueOf(color));
        return button;
    }

    private TextView text(
            String value,
            int size,
            int color,
            boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) {
            view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        }
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(
            value * getResources()
                .getDisplayMetrics().density);
    }

    private boolean alive() {
        return !isFinishing() && !isDestroyed();
    }

    @Override
    protected void onDestroy() {
        LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            activePlanningCancellation;
        if (cancellation != null) {
            cancellation.cancel();
        }
        worker.shutdownNow();
        historyWorker.shutdownNow();
        super.onDestroy();
    }
}
