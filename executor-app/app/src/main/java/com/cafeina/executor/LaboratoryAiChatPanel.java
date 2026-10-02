package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import com.cafeina.runtime.LlamaBridge;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * First chat-style host surface for CAFEÍNA.
 *
 * Conversation and analysis are model-only and receive no tool handles.
 * Obvious action requests are diverted into Goal Lock + per-task permission
 * review before the existing controlled planner is opened.
 */
public final class LaboratoryAiChatPanel extends LinearLayout {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int USER_PANEL = Color.rgb(43, 82, 130);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private static final String MODEL_PREFS = "cafeina_ai_local_model";
    private static final String ACTIVE_MODEL = "active_model_filename";

    private static final int TASK_MAX_INVOCATIONS = 8;
    private static final int TASK_MAX_TOTAL_INPUT_BYTES = 32 * 1024;
    private static final long TASK_MAX_SESSION_MS = 5L * 60L * 1000L;
    private static final int MAX_TRANSCRIPT_ENTRIES = 8;
    private static final int MAX_TRANSCRIPT_CHARS = 8 * 1024;

    private static final class ChatEntry {
        final boolean user;
        final String text;

        ChatEntry(boolean user, String text) {
            this.user = user;
            this.text = text;
        }
    }

    private final Activity activity;
    private final String projectId;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService diagnosticWorker =
        Executors.newSingleThreadExecutor();
    private final ExecutorService persistenceWorker =
        Executors.newSingleThreadExecutor();
    private final List<ChatEntry> transcript = new ArrayList<>();
    private final List<LaboratoryAiChatSessionStore.Entry> persistedEntries =
        new ArrayList<>();
    private final LaboratoryAiChatSessionStore sessionStore;

    private LaboratoryAiChatSessionStore.WorkflowState workflowState =
        LaboratoryAiChatSessionStore.WorkflowState.IDLE;
    private String workflowContractId = "";
    private String workflowScenarioId = "";
    private String workflowReportId = "";
    private String workflowDetail = "";

    private boolean pendingPermissionsLoaded;
    private String pendingActionMessage = "";
    private LaboratoryAiChatRouter.ModeHint pendingActionModeHint =
        LaboratoryAiChatRouter.ModeHint.CREATION;
    private List<LaboratoryAiToolController.Tool> pendingActionTools =
        Collections.emptyList();
    private List<String> pendingSuggestedToolIds =
        Collections.emptyList();
    private boolean pendingPermissionSuggestionConfident;

    private final ScrollView messageScroll;
    private final LinearLayout messages;
    private final EditText input;
    private final Button sendButton;
    private final Button cancelButton;
    private final Button currentDiagnosticButton;
    private final Button currentActionPrimaryButton;
    private final TextView currentActionStatus;
    private final ProgressBar currentActionProgress;
    private final TextView currentActionBudgetStatus;
    private final TextView liveStatus;

    private volatile LaboratoryAiLlamaCppBackend activeBackend;
    private volatile LaboratoryAiLocalPlannerProbe.Cancellation activePlannerCancellation;
    private volatile LaboratoryAiTestAgent.Control activeTestControl;
    private volatile LaboratoryAiTestAgent.Plan latestValidatedPlan;
    private volatile boolean busy;
    private volatile boolean closed;

    public LaboratoryAiChatPanel(Activity activity, String projectId) {
        super(activity);
        if (activity == null || projectId == null) {
            throw new IllegalArgumentException("chat panel context missing");
        }
        this.activity = activity;
        this.projectId = projectId;
        this.sessionStore = new LaboratoryAiChatSessionStore(
            activity.getFilesDir(), projectId);

        setOrientation(VERTICAL);
        setBackgroundColor(BG);

        TextView heading = text("CONVERSA COM A CAFEÍNA", 15, FG, true);
        heading.setPadding(0, 0, 0, dp(6));
        addView(heading, matchWrap());

        TextView note = text(
            "Mensagens comuns e perguntas de análise/viabilidade vão ao modelo "
                + "local sem ferramentas. Pedidos de ação entram no Goal Lock e "
                + "nas permissões antes de qualquer execução.",
            12,
            MUTED,
            false);
        note.setPadding(0, 0, 0, dp(8));
        addView(note, matchWrap());

        currentActionStatus = text("", 13, FG, true);
        currentActionStatus.setPadding(
            dp(12), dp(9), dp(12), dp(9));
        GradientDrawable actionStatusBackground =
            new GradientDrawable();
        actionStatusBackground.setColor(PANEL);
        actionStatusBackground.setCornerRadius(dp(12));
        currentActionStatus.setBackground(actionStatusBackground);
        currentActionStatus.setVisibility(GONE);
        LayoutParams actionStatusParams = matchWrap();
        actionStatusParams.setMargins(0, 0, 0, dp(8));
        addView(currentActionStatus, actionStatusParams);

        currentActionProgress = new ProgressBar(
            activity,
            null,
            android.R.attr.progressBarStyleHorizontal);
        currentActionProgress.setMax(1000);
        currentActionProgress.setIndeterminate(true);
        currentActionProgress.setVisibility(GONE);
        LayoutParams currentProgressParams = matchWrap();
        currentProgressParams.setMargins(0, 0, 0, dp(8));
        addView(currentActionProgress, currentProgressParams);

        currentActionBudgetStatus = text("", 12, MUTED, false);
        currentActionBudgetStatus.setPadding(
            dp(10), 0, dp(10), dp(8));
        currentActionBudgetStatus.setVisibility(GONE);
        addView(currentActionBudgetStatus, matchWrap());

        currentActionPrimaryButton =
            button("CONTINUAR AÇÃO", ACCENT);
        currentActionPrimaryButton.setAllCaps(false);
        currentActionPrimaryButton.setVisibility(GONE);
        LayoutParams primaryActionParams = matchWrap();
        primaryActionParams.setMargins(0, 0, 0, dp(8));
        addView(currentActionPrimaryButton, primaryActionParams);

        Button clearChat = button("LIMPAR CONVERSA LOCAL", PANEL);
        clearChat.setAllCaps(false);
        clearChat.setOnClickListener(v -> confirmClearConversation());
        LayoutParams clearParams = matchWrap();
        clearParams.setMargins(0, 0, 0, dp(8));
        addView(clearChat, clearParams);

        currentDiagnosticButton =
            button("DIAGNÓSTICO DA AÇÃO ATUAL", PANEL);
        currentDiagnosticButton.setAllCaps(false);
        currentDiagnosticButton.setEnabled(false);
        currentDiagnosticButton.setOnClickListener(
            v -> showCurrentActionDiagnostic());
        LayoutParams diagnosticParams = matchWrap();
        diagnosticParams.setMargins(0, 0, 0, dp(8));
        addView(currentDiagnosticButton, diagnosticParams);

        messageScroll = new ScrollView(activity);
        messageScroll.setFillViewport(true);
        messages = new LinearLayout(activity);
        messages.setOrientation(VERTICAL);
        messages.setPadding(0, 0, 0, dp(8));
        messageScroll.addView(messages);
        addView(
            messageScroll,
            new LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f));

        liveStatus = text("", 12, MUTED, false);
        liveStatus.setVisibility(GONE);
        liveStatus.setPadding(dp(8), dp(5), dp(8), dp(5));
        addView(liveStatus, matchWrap());

        LinearLayout inputRow = new LinearLayout(activity);
        inputRow.setOrientation(HORIZONTAL);

        input = new EditText(activity);
        input.setHint("Mensagem para a CAFEÍNA");
        input.setTextColor(FG);
        input.setHintTextColor(MUTED);
        input.setSingleLine(false);
        input.setMaxLines(4);
        input.setImeOptions(EditorInfo.IME_ACTION_SEND);
        input.setBackgroundTintList(ColorStateList.valueOf(MUTED));
        input.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendCurrent();
                return true;
            }
            return false;
        });
        inputRow.addView(
            input,
            new LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        sendButton = button("ENVIAR", ACCENT);
        sendButton.setOnClickListener(v -> sendCurrent());
        LayoutParams sendParams =
            new LayoutParams(dp(92), ViewGroup.LayoutParams.WRAP_CONTENT);
        sendParams.setMargins(dp(8), 0, 0, 0);
        inputRow.addView(sendButton, sendParams);
        addView(inputRow, matchWrap());

        cancelButton = button("CANCELAR RESPOSTA", PANEL);
        cancelButton.setVisibility(GONE);
        cancelButton.setOnClickListener(v -> cancelActiveResponse());
        LayoutParams cancelParams = matchWrap();
        cancelParams.setMargins(0, dp(6), 0, 0);
        addView(cancelButton, cancelParams);

        input.setEnabled(false);
        sendButton.setEnabled(false);
        setLiveStatus("Restaurando conversa local…");
        restoreSessionAsync();
    }

    public void close() {
        if (closed) return;

        if (activePlannerCancellation != null
                || activeTestControl != null) {
            updateWorkflow(
                LaboratoryAiChatSessionStore.WorkflowState.CANCELLED,
                workflowContractId,
                workflowScenarioId,
                workflowReportId,
                "Fluxo cancelado ao fechar a tela");
        }

        closed = true;
        cancelActiveResponse();
        worker.shutdownNow();
        diagnosticWorker.shutdownNow();
        persistenceWorker.shutdown();
    }

    private void confirmClearConversation() {
        if (closed || busy) {
            return;
        }

        String extra;
        synchronized (persistedEntries) {
            extra = workflowContractId.isEmpty()
                ? ""
                : "\n\nImportante: limpar o chat NÃO apaga o Goal Lock, "
                    + "cenários, relatórios ou a memória de conhecimento. "
                    + "Esses registros continuam no laboratório.";
        }

        new AlertDialog.Builder(activity)
            .setTitle("Limpar conversa local?")
            .setMessage(
                "Isso apaga somente o histórico visível deste chat "
                    + "salvo no armazenamento privado do projeto."
                    + extra)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton(
                "LIMPAR CONVERSA",
                (dialog, which) -> clearConversationLocal())
            .show();
    }

    private void clearConversationLocal() {
        if (closed || busy) return;

        synchronized (transcript) {
            transcript.clear();
        }
        synchronized (persistedEntries) {
            persistedEntries.clear();
            workflowState =
                LaboratoryAiChatSessionStore.WorkflowState.IDLE;
            workflowContractId = "";
            workflowScenarioId = "";
            workflowReportId = "";
            workflowDetail = "";
        }
        messages.removeAllViews();
        hideLiveStatus();
        refreshActionDiagnosticButton();

        try {
            persistenceWorker.execute(() -> {
                try {
                    sessionStore.clear();
                } catch (Exception ignored) {
                    // Clearing visible chat never mutates external task state.
                }
            });
        } catch (java.util.concurrent.RejectedExecutionException ignored) {
            // Panel is closing.
        }

        addAssistantMessage(
            "Conversa local limpa. Goal Locks, relatórios, cenários e "
                + "conhecimento do projeto não foram alterados.");
    }

    private void restoreSessionAsync() {
        worker.execute(() -> {
            LaboratoryAiChatSessionStore.Snapshot loaded;
            LaboratoryAiTaskContractStore.Contract contract = null;
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared = null;
            String error = "";

            try {
                loaded = sessionStore.load();
            } catch (Exception failure) {
                loaded = LaboratoryAiChatSessionStore.Snapshot.empty();
                error = String.valueOf(failure.getMessage());
            }

            if (!loaded.contractId.isEmpty()) {
                try {
                    contract = new LaboratoryAiTaskContractStore(
                        activity.getFilesDir(), projectId)
                        .read(loaded.contractId);
                } catch (Exception failure) {
                    if (error.isEmpty()) {
                        error = String.valueOf(failure.getMessage());
                    }
                }
            }

            if (contract != null && contract.resultRecorded) {
                try {
                    LaboratoryAiTestAgentReportStore.Entry recoveredReport =
                        null;
                    for (LaboratoryAiTestAgentReportStore.Entry entry :
                            new LaboratoryAiTestAgentReportStore(
                                activity.getFilesDir(), projectId).list()) {
                        if (contract.contractId.equals(entry.contractId)) {
                            recoveredReport = entry;
                            break;
                        }
                    }

                    if (recoveredReport != null) {
                        LaboratoryAiChatSessionStore.WorkflowState terminal;
                        if ("PASS".equals(recoveredReport.status)) {
                            terminal =
                                LaboratoryAiChatSessionStore.WorkflowState.COMPLETED;
                        } else if ("CANCELLED".equals(recoveredReport.status)) {
                            terminal =
                                LaboratoryAiChatSessionStore.WorkflowState.CANCELLED;
                        } else if ("PAUSED".equals(recoveredReport.status)) {
                            terminal =
                                LaboratoryAiChatSessionStore.WorkflowState.INTERRUPTED;
                        } else {
                            terminal =
                                LaboratoryAiChatSessionStore.WorkflowState.FAILED;
                        }

                        loaded = new LaboratoryAiChatSessionStore.Snapshot(
                            System.currentTimeMillis(),
                            loaded.entries,
                            terminal,
                            contract.contractId,
                            loaded.scenarioId,
                            recoveredReport.reportId,
                            "Relatório recuperado • "
                                + recoveredReport.status);
                        try {
                            sessionStore.save(loaded);
                        } catch (Exception ignored) {
                            // Reconciliation can still be shown in memory.
                        }
                    }
                } catch (Exception failure) {
                    if (error.isEmpty()) {
                        error = String.valueOf(failure.getMessage());
                    }
                }
            }

            if (loaded.workflowState
                    == LaboratoryAiChatSessionStore.WorkflowState.TEST_PREPARED
                    && !loaded.contractId.isEmpty()
                    && !loaded.scenarioId.isEmpty()) {
                try {
                    prepared =
                        LaboratoryAiValidatedPlanExecutionGate.restorePrepared(
                            activity,
                            projectId,
                            loaded.contractId,
                            loaded.scenarioId);
                } catch (Exception failure) {
                    if (error.isEmpty()) {
                        error = String.valueOf(failure.getMessage());
                    }
                }
            }

            final LaboratoryAiChatSessionStore.Snapshot restored = loaded;
            final LaboratoryAiTaskContractStore.Contract restoredContract =
                contract;
            final LaboratoryAiValidatedPlanExecutionGate.Prepared
                restoredPrepared = prepared;
            final String restoreError = error;

            runOnUi(() -> applyRestoredSession(
                restored,
                restoredContract,
                restoredPrepared,
                restoreError));
        });
    }

    private void applyRestoredSession(
            LaboratoryAiChatSessionStore.Snapshot snapshot,
            LaboratoryAiTaskContractStore.Contract contract,
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared,
            String restoreError) {
        if (closed) return;

        messages.removeAllViews();
        synchronized (transcript) {
            transcript.clear();
        }
        synchronized (persistedEntries) {
            persistedEntries.clear();
            persistedEntries.addAll(snapshot.entries);
            workflowState = snapshot.workflowState;
            workflowContractId = snapshot.contractId;
            workflowScenarioId = snapshot.scenarioId;
            workflowReportId = snapshot.reportId;
            workflowDetail = snapshot.statusDetail;
        }

        for (LaboratoryAiChatSessionStore.Entry entry :
                snapshot.entries) {
            addBubble(
                entry.text,
                entry.role
                    == LaboratoryAiChatSessionStore.Role.USER);
            if (entry.modelContext) {
                remember(
                    entry.role
                        == LaboratoryAiChatSessionStore.Role.USER,
                    entry.text);
            }
        }

        hideLiveStatus();
        input.setEnabled(true);
        sendButton.setEnabled(true);

        if (snapshot.entries.isEmpty()) {
            addAssistantMessage(
                "Pode falar comigo normalmente. Se você pedir uma ação no app, "
                    + "eu separo conversa de execução e peço as permissões da tarefa.");
        }

        if (!restoreError.isEmpty()) {
            addAssistantMessage(
                "A conversa visível foi restaurada até onde foi possível, "
                    + "mas uma parte do estado operacional precisa de revisão."
                    + "\nDiagnóstico: " + restoreError);
        }

        LaboratoryAiChatSessionStore.WorkflowState state =
            snapshot.workflowState;
        if (state
                == LaboratoryAiChatSessionStore.WorkflowState.PLANNING
                || state
                == LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING
                || state
                == LaboratoryAiChatSessionStore.WorkflowState.TEST_PAUSED) {
            updateWorkflow(
                LaboratoryAiChatSessionStore.WorkflowState.INTERRUPTED,
                snapshot.contractId,
                snapshot.scenarioId,
                snapshot.reportId,
                "Operação interrompida antes de registrar estado terminal");
            addAssistantMessage(
                "A operação que estava em andamento não será retomada "
                    + "automaticamente. Marquei o fluxo como interrompido "
                    + "para evitar repetir uma ação sem sua confirmação.");
            state = LaboratoryAiChatSessionStore.WorkflowState.INTERRUPTED;
        }

        if (state != LaboratoryAiChatSessionStore.WorkflowState.IDLE) {
            StringBuilder restoredStatus =
                new StringBuilder("Tarefa restaurada • ")
                    .append(workflowStateLabel(state));
            if (!workflowDetail.isEmpty()) {
                restoredStatus.append(" • ")
                    .append(workflowDetail);
            }
            setLiveStatus(restoredStatus.toString());
        }

        refreshActionDiagnosticButton();
        renderRestoredWorkflowActions(
            state,
            contract,
            prepared);
    }

    private static String workflowStateLabel(
            LaboratoryAiChatSessionStore.WorkflowState state) {
        if (state == null) return "estado desconhecido";
        switch (state) {
            case ACTION_REVIEW:
                return "aguardando permissões";
            case GOAL_LOCK_CREATED:
                return "Goal Lock criado";
            case PLANNING:
                return "planejando";
            case PLAN_READY:
                return "plano validado";
            case TEST_PREPARED:
                return "Testadora preparada";
            case TEST_RUNNING:
                return "Testadora em execução";
            case TEST_PAUSED:
                return "Testadora pausada";
            case COMPLETED:
                return "concluída";
            case FAILED:
                return "falha registrada";
            case CANCELLED:
                return "cancelada";
            case INTERRUPTED:
                return "interrompida";
            case IDLE:
            default:
                return "livre";
        }
    }

    private void renderRestoredWorkflowActions(
            LaboratoryAiChatSessionStore.WorkflowState state,
            LaboratoryAiTaskContractStore.Contract contract,
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared) {
        if (closed || state == null) return;

        if (state
                == LaboratoryAiChatSessionStore.WorkflowState.ACTION_REVIEW
                && workflowContractId.isEmpty()) {
            String pendingAction = lastPersistedUserMessage();
            if (!pendingAction.isEmpty()) {
                resumeActionReview(pendingAction);
            } else {
                addAssistantMessage(
                    "Não encontrei o texto da ação que aguardava permissões. "
                        + "Envie o objetivo novamente para continuar.");
            }
            return;
        }

        if (state
                == LaboratoryAiChatSessionStore.WorkflowState.TEST_PREPARED
                && prepared != null) {
            addActionButton(
                "EXECUTAR TESTE • CONSOME GOAL LOCK",
                () -> confirmAndExecutePrepared(prepared));
            return;
        }

        if (contract != null) {
            if (!contract.claimed && !contract.resultRecorded) {
                addActionButton(
                    "CONTINUAR TAREFA • GERAR PLANO",
                    () -> runPlannerInline(contract.contractId));
            } else if (contract.claimed && !contract.resultRecorded) {
                addActionButton(
                    "ABRIR RECUPERAÇÃO DA IA",
                    () -> activity.startActivity(
                        new Intent(
                            activity,
                            LaboratoryAiSessionRecoveryActivity.class)));
            } else {
                addActionButton(
                    "ABRIR RELATÓRIOS DA TESTADORA",
                    () -> activity.startActivity(
                        new Intent(
                            activity,
                            LaboratoryAiTestAgentReportsActivity.class)));
            }
        } else if (!workflowReportId.isEmpty()) {
            addActionButton(
                "ABRIR RELATÓRIOS DA TESTADORA",
                () -> activity.startActivity(
                    new Intent(
                        activity,
                        LaboratoryAiTestAgentReportsActivity.class)));
        }
    }

    private void resumeActionReview(String message) {
        if (closed || busy || message == null || message.trim().isEmpty()) {
            return;
        }
        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(message);
        worker.execute(() -> {
            try {
                List<LaboratoryAiToolController.Tool> available =
                    LaboratoryAiToolController.listAvailable(
                        activity, projectId);
                runOnUi(() -> renderActionPreparation(
                    message,
                    route.modeHint,
                    available));
            } catch (Exception error) {
                runOnUi(() -> addAssistantMessage(
                    "Não consegui retomar as permissões desta tarefa: "
                        + String.valueOf(error.getMessage())));
            }
        });
    }

    private String lastPersistedUserMessage() {
        synchronized (persistedEntries) {
            for (int i = persistedEntries.size() - 1; i >= 0; i--) {
                LaboratoryAiChatSessionStore.Entry entry =
                    persistedEntries.get(i);
                if (entry.role
                        == LaboratoryAiChatSessionStore.Role.USER
                        && !entry.modelContext) {
                    return entry.text;
                }
            }
        }
        return "";
    }

    private void updateWorkflow(
            LaboratoryAiChatSessionStore.WorkflowState state,
            String contractId,
            String scenarioId,
            String reportId,
            String detail) {
        synchronized (persistedEntries) {
            workflowState = state == null
                ? LaboratoryAiChatSessionStore.WorkflowState.IDLE
                : state;
            workflowContractId = contractId == null ? "" : contractId;
            workflowScenarioId = scenarioId == null ? "" : scenarioId;
            workflowReportId = reportId == null ? "" : reportId;
            workflowDetail = boundedStatus(detail);
        }
        if (state
                != LaboratoryAiChatSessionStore.WorkflowState.PLAN_READY) {
            latestValidatedPlan = null;
        }
        if (state
                != LaboratoryAiChatSessionStore.WorkflowState.ACTION_REVIEW) {
            pendingPermissionsLoaded = false;
            pendingActionMessage = "";
            pendingActionTools = Collections.emptyList();
            pendingSuggestedToolIds = Collections.emptyList();
            pendingPermissionSuggestionConfident = false;
        }
        refreshActionDiagnosticButton();
        schedulePersist();
    }

    private void refreshActionDiagnosticButton() {
        if (currentDiagnosticButton == null) return;
        boolean enabled;
        synchronized (persistedEntries) {
            enabled = workflowContractId != null
                && !workflowContractId.isEmpty();
        }
        currentDiagnosticButton.setEnabled(enabled);
        refreshCurrentActionStatus();
    }

    private void refreshCurrentActionStatus() {
        if (currentActionStatus == null) return;

        LaboratoryAiChatSessionStore.WorkflowState state;
        String detail;
        synchronized (persistedEntries) {
            state = workflowState;
            detail = workflowDetail;
        }

        if (state == null
                || state
                    == LaboratoryAiChatSessionStore.WorkflowState.IDLE) {
            currentActionStatus.setText("");
            currentActionStatus.setVisibility(GONE);
            currentActionProgress.setVisibility(GONE);
            refreshCurrentActionPrimaryButton(
                LaboratoryAiChatSessionStore.WorkflowState.IDLE);
            return;
        }

        StringBuilder value = new StringBuilder();
        value.append("AÇÃO ATUAL • ")
            .append(workflowStateLabel(state))
            .append("\n")
            .append(workflowNextStep(state));
        if (detail != null && !detail.isEmpty()
                && state
                    != LaboratoryAiChatSessionStore.WorkflowState.ACTION_REVIEW) {
            value.append("\n")
                .append(detail);
        }
        if ((state == LaboratoryAiChatSessionStore.WorkflowState.PLANNING
                    || state == LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING
                    || state == LaboratoryAiChatSessionStore.WorkflowState.TEST_PAUSED)
                && liveStatus != null
                && liveStatus.getVisibility() == VISIBLE
                && liveStatus.getText() != null
                && liveStatus.getText().length() > 0) {
            value.append("\nAndamento: ")
                .append(liveStatus.getText());
        }
        currentActionStatus.setText(value.toString());
        currentActionStatus.setVisibility(VISIBLE);
        refreshCurrentActionProgressForState(state);
        refreshCurrentActionPrimaryButton(state);
    }

    private void refreshCurrentActionProgressForState(
            LaboratoryAiChatSessionStore.WorkflowState state) {
        if (currentActionProgress == null) return;

        if (state
                == LaboratoryAiChatSessionStore.WorkflowState.PLANNING
                || state
                    == LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING
                || state
                    == LaboratoryAiChatSessionStore.WorkflowState.TEST_PAUSED) {
            currentActionProgress.setVisibility(VISIBLE);
            if (currentActionProgress.getProgress() <= 0) {
                currentActionProgress.setIndeterminate(true);
            }
        } else {
            currentActionProgress.setVisibility(GONE);
            currentActionProgress.setIndeterminate(true);
            currentActionProgress.setProgress(0);
        }

        if (state
                != LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING
                && state
                    != LaboratoryAiChatSessionStore.WorkflowState.TEST_PAUSED) {
            currentActionBudgetStatus.setText("");
            currentActionBudgetStatus.setVisibility(GONE);
        }
    }

    private void renderPlannerProgress(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (snapshot == null || currentActionProgress == null) return;
        currentActionProgress.setVisibility(VISIBLE);

        if (snapshot.state
                == LaboratoryAiExecutionStatus.State.COMPLETED) {
            currentActionProgress.setIndeterminate(false);
            currentActionProgress.setProgress(1000);
            return;
        }

        if (snapshot.phase
                == LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT
                && snapshot.promptTokens > 0) {
            currentActionProgress.setIndeterminate(false);
            currentActionProgress.setProgress(
                progressFraction(
                    snapshot.promptTokensProcessed,
                    snapshot.promptTokens));
        } else {
            currentActionProgress.setIndeterminate(true);
        }
    }

    private void renderTestBudget(
            LaboratoryAiSessionController.Snapshot snapshot) {
        if (currentActionBudgetStatus == null) return;
        if (snapshot == null) {
            currentActionBudgetStatus.setText("");
            currentActionBudgetStatus.setVisibility(GONE);
            return;
        }

        String text =
            "ORÇAMENTO • "
                + snapshot.invocationsRemaining
                + " chamada(s) restante(s) • "
                + formatBytes(snapshot.inputBytesRemaining)
                + " de entrada • "
                + formatElapsed(snapshot.remainingMs)
                + " restantes";
        currentActionBudgetStatus.setText(text);
        currentActionBudgetStatus.setVisibility(VISIBLE);
    }

    private static String formatBytes(int bytes) {
        int safe = Math.max(0, bytes);
        if (safe < 1024) return safe + " B";
        double kib = safe / 1024.0;
        return String.format(Locale.ROOT, "%.1f KiB", kib);
    }

    private void renderTestProgress(
            int completedSteps,
            int totalSteps) {
        if (currentActionProgress == null) return;
        currentActionProgress.setVisibility(VISIBLE);
        if (totalSteps <= 0) {
            currentActionProgress.setIndeterminate(true);
            return;
        }
        currentActionProgress.setIndeterminate(false);
        currentActionProgress.setProgress(
            progressFraction(completedSteps, totalSteps));
    }

    private static int progressFraction(int completed, int total) {
        if (completed <= 0 || total <= 0) return 0;
        if (completed >= total) return 1000;
        return (int) Math.max(
            0L,
            Math.min(
                1000L,
                Math.round(completed * 1000.0 / total)));
    }

    private void refreshCurrentActionPrimaryButton(
            LaboratoryAiChatSessionStore.WorkflowState state) {
        if (currentActionPrimaryButton == null) return;

        currentActionPrimaryButton.setVisibility(GONE);
        currentActionPrimaryButton.setEnabled(true);
        currentActionPrimaryButton.setOnClickListener(null);

        if (state == null
                || state
                    == LaboratoryAiChatSessionStore.WorkflowState.IDLE) {
            return;
        }

        switch (state) {
            case ACTION_REVIEW:
                if (!pendingPermissionsLoaded) {
                    currentActionPrimaryButton.setText(
                        "CARREGANDO PERMISSÕES…");
                    currentActionPrimaryButton.setEnabled(false);
                } else if (pendingActionTools.isEmpty()) {
                    currentActionPrimaryButton.setText(
                        "ABRIR PERMISSÕES GLOBAIS");
                    currentActionPrimaryButton.setEnabled(!busy);
                    currentActionPrimaryButton.setOnClickListener(v ->
                        activity.startActivity(
                            new Intent(
                                activity,
                                LaboratoryAiPermissionsActivity.class)));
                } else if (pendingPermissionSuggestionConfident) {
                    currentActionPrimaryButton.setText(
                        "PERMITIR SUGESTÃO E GERAR PLANO");
                    currentActionPrimaryButton.setEnabled(!busy);
                    currentActionPrimaryButton.setOnClickListener(v ->
                        createGoalLock(
                            pendingActionMessage,
                            pendingActionModeHint,
                            pendingSuggestedToolIds,
                            true));
                } else {
                    currentActionPrimaryButton.setText(
                        "ESCOLHER PERMISSÕES DA TAREFA");
                    currentActionPrimaryButton.setEnabled(!busy);
                    currentActionPrimaryButton.setOnClickListener(v ->
                        showTaskPermissionDialog(
                            pendingActionMessage,
                            pendingActionModeHint,
                            pendingActionTools,
                            pendingSuggestedToolIds));
                }
                break;
            case GOAL_LOCK_CREATED:
                currentActionPrimaryButton.setText(
                    "GERAR PLANO • NÃO EXECUTAR");
                currentActionPrimaryButton.setEnabled(!busy);
                currentActionPrimaryButton.setOnClickListener(v -> {
                    String contractId;
                    synchronized (persistedEntries) {
                        contractId = workflowContractId;
                    }
                    if (contractId != null && !contractId.isEmpty()) {
                        runPlannerInline(contractId);
                    }
                });
                break;
            case PLANNING:
                currentActionPrimaryButton.setText(
                    "CANCELAR PLANEJAMENTO");
                currentActionPrimaryButton.setEnabled(
                    activePlannerCancellation != null);
                currentActionPrimaryButton.setOnClickListener(
                    v -> cancelActiveResponse());
                break;
            case PLAN_READY:
                if (latestValidatedPlan != null) {
                    currentActionPrimaryButton.setText(
                        "PREPARAR TESTADORA • NÃO EXECUTAR");
                    currentActionPrimaryButton.setEnabled(!busy);
                    currentActionPrimaryButton.setOnClickListener(v -> {
                        String contractId;
                        LaboratoryAiTestAgent.Plan plan =
                            latestValidatedPlan;
                        synchronized (persistedEntries) {
                            contractId = workflowContractId;
                        }
                        if (contractId != null
                                && !contractId.isEmpty()
                                && plan != null) {
                            prepareTestAgentInline(contractId, plan);
                        }
                    });
                } else {
                    currentActionPrimaryButton.setText(
                        "REGERAR PLANO PARA CONTINUAR");
                    currentActionPrimaryButton.setEnabled(!busy);
                    currentActionPrimaryButton.setOnClickListener(v -> {
                        String contractId;
                        synchronized (persistedEntries) {
                            contractId = workflowContractId;
                        }
                        if (contractId != null
                                && !contractId.isEmpty()) {
                            runPlannerInline(contractId);
                        }
                    });
                }
                break;
            case TEST_PREPARED:
                currentActionPrimaryButton.setText(
                    "REVISAR E EXECUTAR TESTE");
                currentActionPrimaryButton.setEnabled(!busy);
                currentActionPrimaryButton.setOnClickListener(
                    v -> restoreAndConfirmPreparedTest());
                break;
            case TEST_RUNNING:
                if (activeTestControl != null
                        && activeTestControl.isPauseRequested()) {
                    currentActionPrimaryButton.setText(
                        "PAUSA SOLICITADA • AGUARDANDO PONTO SEGURO");
                    currentActionPrimaryButton.setEnabled(false);
                } else {
                    currentActionPrimaryButton.setText("PAUSAR TESTE");
                    currentActionPrimaryButton.setEnabled(
                        activeTestControl != null);
                    currentActionPrimaryButton.setOnClickListener(
                        v -> pauseActiveTest());
                }
                break;
            case TEST_PAUSED:
                currentActionPrimaryButton.setText("CONTINUAR TESTE");
                currentActionPrimaryButton.setEnabled(
                    activeTestControl != null);
                currentActionPrimaryButton.setOnClickListener(
                    v -> resumeActiveTest());
                break;
            case COMPLETED:
                currentActionPrimaryButton.setText(
                    "ABRIR RELATÓRIO DA TESTADORA");
                currentActionPrimaryButton.setOnClickListener(v ->
                    activity.startActivity(
                        new Intent(
                            activity,
                            LaboratoryAiTestAgentReportsActivity.class)));
                break;
            case FAILED:
            case INTERRUPTED:
                currentActionPrimaryButton.setText(
                    "ABRIR DIAGNÓSTICO DA AÇÃO");
                currentActionPrimaryButton.setOnClickListener(
                    v -> showCurrentActionDiagnostic());
                break;
            case CANCELLED:
                currentActionPrimaryButton.setText(
                    "VER DIAGNÓSTICO DA AÇÃO");
                currentActionPrimaryButton.setOnClickListener(
                    v -> showCurrentActionDiagnostic());
                break;
            default:
                return;
        }

        currentActionPrimaryButton.setVisibility(VISIBLE);
    }

    private void restoreAndConfirmPreparedTest() {
        if (closed || busy) return;

        final String contractId;
        final String scenarioId;
        synchronized (persistedEntries) {
            contractId = workflowContractId;
            scenarioId = workflowScenarioId;
        }
        if (contractId == null || contractId.isEmpty()
                || scenarioId == null || scenarioId.isEmpty()) {
            showCurrentActionDiagnostic();
            return;
        }

        setLiveStatus("Revalidando cenário preparado…");
        worker.execute(() -> {
            try {
                LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
                    LaboratoryAiValidatedPlanExecutionGate.restorePrepared(
                        activity,
                        projectId,
                        contractId,
                        scenarioId);
                runOnUi(() -> {
                    if (closed) return;
                    hideLiveStatus();
                    confirmAndExecutePrepared(prepared);
                });
            } catch (Exception error) {
                runOnUi(() -> {
                    if (closed) return;
                    hideLiveStatus();
                    addAssistantMessage(
                        "Não consegui revalidar o cenário preparado. "
                            + "Nenhuma execução foi iniciada."
                            + "\n" + String.valueOf(error.getMessage()));
                    updateWorkflow(
                        LaboratoryAiChatSessionStore.WorkflowState.FAILED,
                        contractId,
                        scenarioId,
                        "",
                        "Falha ao revalidar cenário preparado");
                });
            }
        });
    }

    private static String workflowNextStep(
            LaboratoryAiChatSessionStore.WorkflowState state) {
        if (state == null) return "Aguardando próxima ação.";
        switch (state) {
            case ACTION_REVIEW:
                return "Próximo: revisar e confirmar as permissões desta tarefa.";
            case GOAL_LOCK_CREATED:
                return "Próximo: gerar o plano sem executar ferramentas.";
            case PLANNING:
                return "Agora: o planejador está montando e validando o plano.";
            case PLAN_READY:
                return "Próximo: revisar o plano e preparar a Testadora.";
            case TEST_PREPARED:
                return "Próximo: confirmar ou cancelar a execução do teste.";
            case TEST_RUNNING:
                return "Agora: a Testadora está executando o cenário aprovado.";
            case TEST_PAUSED:
                return "Pausada em ponto seguro: continue ou cancele quando quiser.";
            case COMPLETED:
                return "Concluído: revise o resultado ou o relatório se quiser.";
            case FAILED:
                return "Próximo: abra o diagnóstico da ação antes de repetir.";
            case CANCELLED:
                return "Cancelado: nenhuma nova tentativa será iniciada sozinha.";
            case INTERRUPTED:
                return "Próximo: diagnosticar e escolher conscientemente como retomar.";
            case IDLE:
            default:
                return "Aguardando próxima ação.";
        }
    }

    private void showCurrentActionDiagnostic() {
        if (closed) return;

        final String contractId;
        final LaboratoryAiChatSessionStore.WorkflowState liveWorkflow;
        final String liveDetail;
        synchronized (persistedEntries) {
            contractId = workflowContractId;
            liveWorkflow = workflowState;
            liveDetail = workflowDetail;
        }
        if (contractId == null || contractId.isEmpty()) {
            return;
        }

        final String liveStatusText =
            liveStatus.getVisibility() == VISIBLE
                ? liveStatus.getText().toString()
                : "";
        final boolean operationRunning =
            liveWorkflow
                    == LaboratoryAiChatSessionStore.WorkflowState.PLANNING
                || liveWorkflow
                    == LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING
                || liveWorkflow
                    == LaboratoryAiChatSessionStore.WorkflowState.TEST_PAUSED;

        currentDiagnosticButton.setEnabled(false);
        if (!operationRunning) {
            setLiveStatus("Lendo diagnóstico desta ação…");
        }

        diagnosticWorker.execute(() -> {
            try {
                LaboratoryAiActionDiagnostic.Snapshot diagnosis =
                    LaboratoryAiActionDiagnostic.inspect(
                        activity.getFilesDir(),
                        projectId,
                        contractId);
                final String rendered =
                    renderActionDiagnostic(
                        diagnosis,
                        liveWorkflow,
                        liveDetail,
                        liveStatusText,
                        operationRunning);
                runOnUi(() -> {
                    if (closed) return;
                    if (!operationRunning) {
                        hideLiveStatus();
                    }
                    refreshActionDiagnosticButton();
                    showDiagnosticDialog(rendered);
                });
            } catch (Exception error) {
                final String reason = String.valueOf(error.getMessage());
                runOnUi(() -> {
                    if (closed) return;
                    if (!operationRunning) {
                        hideLiveStatus();
                    }
                    refreshActionDiagnosticButton();
                    new AlertDialog.Builder(activity)
                        .setTitle("Diagnóstico da ação")
                        .setMessage(
                            "Não consegui ler o diagnóstico desta ação."
                                + "\n\n" + reason)
                        .setPositiveButton("FECHAR", null)
                        .show();
                });
            }
        });
    }

    private String renderActionDiagnostic(
            LaboratoryAiActionDiagnostic.Snapshot snapshot,
            LaboratoryAiChatSessionStore.WorkflowState liveWorkflow,
            String liveDetail,
            String liveStatusText,
            boolean operationRunning) {
        StringBuilder out = new StringBuilder();
        out.append("AÇÃO ATUAL")
            .append("\nEtapa: ")
            .append(operationRunning
                ? workflowStateLabel(liveWorkflow)
                : actionStageLabel(snapshot.stage))
            .append("\nModo: ")
            .append(snapshot.mode)
            .append("\nFerramentas autorizadas: ")
            .append(snapshot.allowedToolCount)
            .append("\nGoal Lock consumido: ")
            .append(snapshot.goalLockClaimed ? "SIM" : "NÃO")
            .append("\nResultado terminal registrado: ")
            .append(snapshot.resultRecorded ? "SIM" : "NÃO")
            .append("\n\nDiagnóstico: ")
            .append(snapshot.explanation)
            .append("\nO que fazer agora: ")
            .append(snapshot.nextStep)
            .append("\nCódigo técnico: ")
            .append(snapshot.nextCheck);

        if (operationRunning) {
            out.append("\n\nSTATUS AO VIVO")
                .append("\n")
                .append(liveStatusText == null || liveStatusText.isEmpty()
                    ? "Operação em andamento; aguardando a próxima amostra."
                    : liveStatusText);
            if (liveDetail != null && !liveDetail.isEmpty()) {
                out.append("\n")
                    .append(liveDetail);
            }
            out.append(
                "\nOs dados terminais abaixo podem ainda refletir a última "
                    + "etapa persistida; eles serão atualizados quando a "
                    + "operação atual terminar.");
        }

        if (snapshot.planner != null) {
            out.append("\n\nPLANEJADOR")
                .append("\nEstado: ")
                .append(snapshot.planner.state)
                .append("\nFase final: ")
                .append(phaseLabel(snapshot.planner.phase))
                .append("\nDuração: ")
                .append(formatElapsed(snapshot.planner.elapsedMs))
                .append("\nTentativa: ")
                .append(snapshot.planner.attempt)
                .append("/")
                .append(snapshot.planner.maxAttempts)
                .append("\nPrompt: ")
                .append(snapshot.planner.promptTokensProcessed)
                .append("/")
                .append(snapshot.planner.promptTokens)
                .append(" tokens • ")
                .append(snapshot.planner.promptEvalMs)
                .append(" ms")
                .append("\nGeração: ")
                .append(snapshot.planner.generatedTokens)
                .append("/")
                .append(snapshot.planner.maxGeneratedTokens)
                .append(" tokens • ")
                .append(snapshot.planner.tokenGenerationMs)
                .append(" ms");

            if (snapshot.plannerDiagnostic != null) {
                out.append("\nClassificação: ")
                    .append(snapshot.plannerDiagnostic.code.name());
            }
        } else {
            out.append("\n\nPLANEJADOR")
                .append("\nAinda não há execução terminal registrada.");
        }

        if (snapshot.testReport != null) {
            out.append("\n\nTESTADORA")
                .append("\nStatus: ")
                .append(snapshot.testReport.status)
                .append("\nPassos: ")
                .append(snapshot.testReport.executedSteps)
                .append("/")
                .append(snapshot.testReport.plannedSteps)
                .append("\nPassaram: ")
                .append(snapshot.testReport.passed)
                .append(" • Falharam: ")
                .append(snapshot.testReport.failed)
                .append("\nRelatório: ")
                .append(snapshot.testReport.reportId);
            if (snapshot.testSession != null) {
                out.append("\nChamadas usadas: ")
                    .append(snapshot.testSession.invocationsUsed)
                    .append("/")
                    .append(snapshot.testSession.maxInvocations)
                    .append("\nEntrada usada: ")
                    .append(formatBytes(snapshot.testSession.inputBytesUsed))
                    .append("/")
                    .append(formatBytes(
                        snapshot.testSession.maxTotalInputBytes))
                    .append("\nEstado da sessão: ")
                    .append(snapshot.testSession.state);
            }
        } else {
            out.append("\n\nTESTADORA")
                .append("\nNenhum relatório terminal registrado.");
        }

        out.append(
            "\n\nSomente leitura: este diagnóstico não executa, "
                + "não corrige e não altera permissões.");
        return out.toString();
    }

    private void showDiagnosticDialog(String details) {
        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(activity);
        scroll.addView(body);
        new AlertDialog.Builder(activity)
            .setTitle("Diagnóstico da ação atual")
            .setView(scroll)
            .setNeutralButton(
                "VER HISTÓRICO COMPLETO",
                (dialog, which) -> activity.startActivity(
                    new Intent(
                        activity,
                        LaboratoryAiDiagnosticsActivity.class)))
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private static String actionStageLabel(
            LaboratoryAiActionDiagnostic.Stage stage) {
        if (stage == null) return "desconhecida";
        switch (stage) {
            case GOAL_LOCK_READY:
                return "Goal Lock pronto";
            case PLANNER_COMPLETED:
                return "planejamento concluído";
            case PLANNER_FAILED:
                return "planejamento com falha";
            case TEST_AGENT_RUNNING_OR_INTERRUPTED:
                return "Testadora consumiu o Goal Lock sem resultado terminal";
            case TEST_AGENT_COMPLETED:
                return "Teste concluído";
            case UNKNOWN:
            default:
                return "desconhecida";
        }
    }

    private void persistVisibleEntry(
            LaboratoryAiChatSessionStore.Role role,
            String value,
            boolean modelContext) {
        String clean = boundedChatText(value);
        if (clean.isEmpty()) return;

        LaboratoryAiChatSessionStore.Entry entry =
            LaboratoryAiChatSessionStore.Entry.create(
                role,
                clean,
                modelContext);
        synchronized (persistedEntries) {
            persistedEntries.add(entry);
            while (persistedEntries.size()
                    > LaboratoryAiChatSessionStore.MAX_ENTRIES) {
                persistedEntries.remove(0);
            }
        }
        schedulePersist();
    }

    private void schedulePersist() {
        final LaboratoryAiChatSessionStore.Snapshot snapshot;
        synchronized (persistedEntries) {
            snapshot = new LaboratoryAiChatSessionStore.Snapshot(
                System.currentTimeMillis(),
                new ArrayList<>(persistedEntries),
                workflowState,
                workflowContractId,
                workflowScenarioId,
                workflowReportId,
                workflowDetail);
        }

        try {
            persistenceWorker.execute(() -> {
                try {
                    sessionStore.save(snapshot);
                } catch (Exception ignored) {
                    // Chat persistence never controls model/tool execution.
                }
            });
        } catch (java.util.concurrent.RejectedExecutionException ignored) {
            // Panel is already closing.
        }
    }

    private static String boundedChatText(String value) {
        if (value == null) return "";
        String clean = value.trim();
        if (clean.length()
                <= LaboratoryAiChatSessionStore.MAX_ENTRY_CHARS) {
            return clean;
        }
        return clean.substring(
            0,
            LaboratoryAiChatSessionStore.MAX_ENTRY_CHARS);
    }

    private static String boundedStatus(String value) {
        if (value == null) return "";
        String clean = value.trim();
        if (clean.length()
                <= LaboratoryAiChatSessionStore.MAX_STATUS_CHARS) {
            return clean;
        }
        return clean.substring(
            0,
            LaboratoryAiChatSessionStore.MAX_STATUS_CHARS);
    }

    private void sendCurrent() {
        if (closed || busy) return;
        String message = input.getText().toString().trim();
        if (message.isEmpty()) return;
        input.setText("");

        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(message);
        boolean modelOnly =
            route.kind != LaboratoryAiChatRouter.Kind.ACTION;
        addUserMessage(message, modelOnly);

        if (route.kind == LaboratoryAiChatRouter.Kind.ACTION) {
            handleAction(message, route);
        } else {
            runConversation(message, route.kind);
        }
    }

    private void runConversation(
            String message,
            LaboratoryAiChatRouter.Kind kind) {
        final String selected = selectedModelFileName();
        if (selected.isEmpty()) {
            addAssistantMessage(
                "Ainda não há modelo local ativo. Selecione um GGUF nos "
                    + "controles logo abaixo do chat e envie a mensagem novamente.");
            return;
        }

        setBusy(true);
        setLiveStatus(
            kind == LaboratoryAiChatRouter.Kind.ANALYSIS
                ? "Analisando viabilidade no modelo local…"
                : "Preparando modelo local…");
        worker.execute(() -> {
            LaboratoryAiLlamaCppBackend backend = null;
            try {
                LaboratoryAiLocalModelCatalog.Model model =
                    LaboratoryAiLocalModelCatalog.resolve(
                        activity.getFilesDir(), selected);

                backend = LaboratoryAiLocalModelPreflight.open(
                    activity,
                    model.modelFile,
                    LaboratoryAiLlamaCppBackend.RuntimeConfig.chatDefaults(),
                    new LaboratoryAiLlamaCppBackend.GenerationObserver() {
                        @Override
                        public void onNativePhase(int phase) {
                            updatePhaseStatus(phase);
                        }

                        @Override
                        public void onNativeMetrics(
                                LlamaBridge.GenerationMetrics metrics) {
                            updateMetricStatus(metrics);
                        }
                    });
                activeBackend = backend;

                String response = backend.generate(
                    new LaboratoryAiLocalModelBackend.GenerationRequest(
                        buildConversationPrompt(message, kind),
                        8 * 1024,
                        0.65f,
                        20261002L));
                final String clean = response == null
                    ? ""
                    : response.trim();

                runOnUi(() -> {
                    if (closed) return;
                    if (clean.isEmpty()) {
                        addAssistantMessage(
                            "O modelo terminou sem produzir texto.");
                    } else {
                        addAssistantConversationMessage(clean);
                    }
                    setBusy(false);
                    if (!clean.isEmpty()
                            && kind
                                == LaboratoryAiChatRouter.Kind.ANALYSIS) {
                        addActionButton(
                            "TRANSFORMAR ANÁLISE EM AÇÃO",
                            () -> showAnalysisActionDialog(message));
                    }
                });
            } catch (Exception error) {
                final String reason = String.valueOf(error.getMessage());
                runOnUi(() -> {
                    if (closed) return;
                    addAssistantMessage(
                        "A resposta local não foi concluída. "
                            + (reason == null || "null".equals(reason)
                                ? error.getClass().getSimpleName()
                                : reason));
                    setBusy(false);
                });
            } finally {
                activeBackend = null;
                if (backend != null) {
                    backend.close();
                }
            }
        });
    }

    private void handleAction(
            String message,
            LaboratoryAiChatRouter.Route route) {
        beginControlledAction(message, route.modeHint);
    }

    private void showAnalysisActionDialog(String sourceMessage) {
        if (closed || busy || sourceMessage == null
                || sourceMessage.trim().isEmpty()) {
            return;
        }

        EditText goal = new EditText(activity);
        goal.setText(sourceMessage.trim());
        goal.setTextColor(FG);
        goal.setHintTextColor(MUTED);
        goal.setSelectAllOnFocus(false);
        goal.setSelection(goal.getText().length());
        goal.setMinLines(3);
        goal.setMaxLines(8);
        goal.setPadding(dp(14), dp(8), dp(14), dp(8));

        AlertDialog dialog = new AlertDialog.Builder(activity)
            .setTitle("Transformar análise em ação")
            .setMessage(
                "Revise o objetivo abaixo. Ele só poderá virar Goal Lock "
                    + "depois que você confirmar as permissões da tarefa. "
                    + "Nada será executado nesta etapa.")
            .setView(goal)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton(
                "CONTINUAR PARA PERMISSÕES",
                null)
            .create();

        dialog.setOnShowListener(ignored ->
            dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String objective =
                        goal.getText().toString().trim();
                    if (objective.isEmpty()) {
                        goal.setError("Defina o objetivo da ação");
                        return;
                    }
                    if (objective.length()
                            > LaboratoryAiTaskContractStore.MAX_GOAL_CHARS) {
                        goal.setError(
                            "Objetivo deve ter no máximo "
                                + LaboratoryAiTaskContractStore.MAX_GOAL_CHARS
                                + " caracteres");
                        return;
                    }

                    dialog.dismiss();
                    addUserMessage(objective, false);
                    beginControlledAction(
                        objective,
                        LaboratoryAiChatRouter.ModeHint.LEARNING);
                }));
        dialog.show();
    }

    private void beginControlledAction(
            String message,
            LaboratoryAiChatRouter.ModeHint modeHint) {
        pendingPermissionsLoaded = false;
        pendingActionMessage = message == null ? "" : message;
        pendingActionModeHint = modeHint == null
            ? LaboratoryAiChatRouter.ModeHint.CREATION
            : modeHint;
        pendingActionTools = Collections.emptyList();
        pendingSuggestedToolIds = Collections.emptyList();
        pendingPermissionSuggestionConfident = false;

        updateWorkflow(
            LaboratoryAiChatSessionStore.WorkflowState.ACTION_REVIEW,
            "",
            "",
            "",
            "Aguardando seleção de permissões da tarefa");
        addAssistantMessage(
            "Objetivo de ação confirmado. Não executei nada. "
                + "Agora vou preparar somente as permissões necessárias "
                + "antes de criar o Goal Lock.");

        worker.execute(() -> {
            try {
                List<LaboratoryAiToolController.Tool> available =
                    LaboratoryAiToolController.listAvailable(
                        activity, projectId);
                runOnUi(() -> renderActionPreparation(
                    message, modeHint, available));
            } catch (Exception error) {
                runOnUi(() -> addAssistantMessage(
                    "Não consegui ler as permissões atuais: "
                        + String.valueOf(error.getMessage())));
            }
        });
    }

    private void renderActionPreparation(
            String message,
            LaboratoryAiChatRouter.ModeHint modeHint,
            List<LaboratoryAiToolController.Tool> available) {
        if (closed) return;
        List<LaboratoryAiToolController.Tool> safe =
            available == null
                ? Collections.emptyList()
                : available;

        pendingPermissionsLoaded = true;
        pendingActionMessage = message == null ? "" : message;
        pendingActionModeHint = modeHint == null
            ? LaboratoryAiChatRouter.ModeHint.CREATION
            : modeHint;
        pendingActionTools = Collections.unmodifiableList(
            new ArrayList<>(safe));
        pendingSuggestedToolIds = Collections.emptyList();
        pendingPermissionSuggestionConfident = false;

        if (safe.isEmpty()) {
            refreshCurrentActionStatus();
            addAssistantMessage(
                "Nenhuma ferramenta STABLE está liberada para a IA neste "
                    + "projeto. O pedido continua intacto e nada foi executado. "
                    + "Use o botão principal da AÇÃO ATUAL para abrir as "
                    + "permissões globais.");
            return;
        }

        LaboratoryAiPermissionSuggestion.Result suggestion =
            LaboratoryAiPermissionSuggestion.suggest(message, safe);
        pendingSuggestedToolIds = Collections.unmodifiableList(
            new ArrayList<>(suggestion.suggestedToolIds));
        pendingPermissionSuggestionConfident = suggestion.confident;
        refreshCurrentActionStatus();

        StringBuilder names = new StringBuilder();
        for (LaboratoryAiToolController.Tool tool : safe) {
            if (names.length() > 0) names.append(", ");
            names.append(tool.toolId);
        }

        String permissionMessage;
        if (suggestion.confident) {
            permissionMessage =
                "Para reduzir os cliques, preparei uma sugestão de menor "
                    + "permissão para esta tarefa: "
                    + String.join(", ", suggestion.suggestedToolIds)
                    + ". Isso ainda NÃO é autorização. Você pode revisar, "
                    + "desmarcar ou adicionar ferramentas antes de confirmar.";
        } else {
            permissionMessage =
                "Não encontrei uma sugestão de ferramentas com confiança "
                    + "suficiente, então não marquei nada automaticamente. "
                    + "Ferramentas STABLE disponíveis: " + names + ".";
        }

        addAssistantMessage(
            permissionMessage
                + "\nOrçamento inicial: " + TASK_MAX_INVOCATIONS
                + " chamadas • " + (TASK_MAX_TOTAL_INPUT_BYTES / 1024)
                + " KiB • " + (TASK_MAX_SESSION_MS / 60_000L) + " min.");

        if (suggestion.confident) {
            addActionButton(
                "REVISAR PERMISSÕES DESTA TAREFA",
                () -> showTaskPermissionDialog(
                    message,
                    modeHint,
                    safe,
                    suggestion.suggestedToolIds));
        }

        addActionButton(
            "REVISAR PERMISSÕES GLOBAIS",
            () -> activity.startActivity(
                new Intent(
                    activity,
                    LaboratoryAiPermissionsActivity.class)));
    }

    private void showTaskPermissionDialog(
            String message,
            LaboratoryAiChatRouter.ModeHint modeHint,
            List<LaboratoryAiToolController.Tool> tools,
            List<String> suggestedToolIds) {
        if (tools == null || tools.isEmpty()) return;

        List<String> suggestions = suggestedToolIds == null
            ? Collections.emptyList()
            : suggestedToolIds;
        String[] labels = new String[tools.size()];
        boolean[] checked = new boolean[tools.size()];
        for (int i = 0; i < tools.size(); i++) {
            LaboratoryAiToolController.Tool tool = tools.get(i);
            labels[i] = tool.toolId + " • " + tool.version;
            checked[i] = suggestions.contains(tool.toolId);
        }

        String modeLabel =
            modeHint == LaboratoryAiChatRouter.ModeHint.LEARNING
                ? "APRENDIZADO"
                : "CRIAÇÃO";

        AlertDialog dialog = new AlertDialog.Builder(activity)
            .setTitle("Permissões desta tarefa • " + modeLabel)
            .setMessage(
                (suggestions.isEmpty()
                    ? "Escolha somente as ferramentas que esta tarefa poderá usar."
                    : "As sugestões de menor permissão já estão marcadas. "
                        + "Revise antes de confirmar; você continua no controle.")
                    + "\n\nOrçamento inicial: "
                    + TASK_MAX_INVOCATIONS + " chamadas • "
                    + (TASK_MAX_TOTAL_INPUT_BYTES / 1024) + " KiB • "
                    + (TASK_MAX_SESSION_MS / 60_000L) + " min.\n"
                    + "Criar o Goal Lock não executa ferramenta.")
            .setMultiChoiceItems(
                labels,
                checked,
                (whichDialog, which, isChecked) ->
                    checked[which] = isChecked)
            .setNegativeButton("CANCELAR", null)
            .setNeutralButton(
                "TROCAR MODO",
                null)
            .setPositiveButton(
                "CRIAR GOAL LOCK",
                null)
            .create();

        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL)
                .setOnClickListener(v -> {
                    dialog.dismiss();
                    LaboratoryAiChatRouter.ModeHint other =
                        modeHint == LaboratoryAiChatRouter.ModeHint.LEARNING
                            ? LaboratoryAiChatRouter.ModeHint.CREATION
                            : LaboratoryAiChatRouter.ModeHint.LEARNING;
                    showTaskPermissionDialog(
                        message,
                        other,
                        tools,
                        suggestions);
                });

            dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    List<String> selected = new ArrayList<>();
                    for (int i = 0; i < checked.length; i++) {
                        if (checked[i]) {
                            selected.add(tools.get(i).toolId);
                        }
                    }
                    if (selected.isEmpty()) {
                        addAssistantMessage(
                            "Nenhuma ferramenta foi selecionada. "
                                + "O Goal Lock não foi criado.");
                        dialog.dismiss();
                        return;
                    }
                    dialog.dismiss();
                    createGoalLock(
                        message,
                        modeHint,
                        selected,
                        false);
                });
        });
        dialog.show();
    }

    private void createGoalLock(
            String message,
            LaboratoryAiChatRouter.ModeHint modeHint,
            List<String> selectedToolIds,
            boolean generatePlanAfterCreation) {
        setLiveStatus("Criando Goal Lock…");
        worker.execute(() -> {
            try {
                LaboratoryAiSessionController.Policy policy =
                    new LaboratoryAiSessionController.Policy(
                        selectedToolIds,
                        TASK_MAX_INVOCATIONS,
                        TASK_MAX_TOTAL_INPUT_BYTES,
                        TASK_MAX_SESSION_MS);
                LaboratoryAiTaskContractStore store =
                    new LaboratoryAiTaskContractStore(
                        activity.getFilesDir(), projectId);
                LaboratoryAiTaskContractStore.Mode mode =
                    modeHint == LaboratoryAiChatRouter.ModeHint.LEARNING
                        ? LaboratoryAiTaskContractStore.Mode.LEARNING
                        : LaboratoryAiTaskContractStore.Mode.CREATION;
                LaboratoryAiTaskContractStore.Contract contract =
                    store.create(mode, message, policy);

                runOnUi(() -> {
                    if (closed) return;
                    hideLiveStatus();
                    updateWorkflow(
                        LaboratoryAiChatSessionStore.WorkflowState
                            .GOAL_LOCK_CREATED,
                        contract.contractId,
                        "",
                        "",
                        "Goal Lock criado e ainda não consumido");
                    addAssistantMessage(
                        "Goal Lock criado. Objetivo travado em "
                            + contract.mode.name()
                            + ", com " + contract.allowedToolIds.size()
                            + " ferramenta(s). Nada foi executado.\n"
                            + "Contrato: " + contract.contractId);
                    if (generatePlanAfterCreation) {
                        addAssistantMessage(
                            "Permissões confirmadas. Vou gerar o plano agora; "
                                + "essa etapa ainda não executa ferramentas "
                                + "nem consome o Goal Lock.");
                        runPlannerInline(contract.contractId);
                    }
                });
            } catch (Exception error) {
                runOnUi(() -> {
                    hideLiveStatus();
                    addAssistantMessage(
                        "O Goal Lock não foi criado: "
                            + String.valueOf(error.getMessage()));
                });
            }
        });
    }

    private void runPlannerInline(String contractId) {
        if (closed || busy) return;

        final String selected = selectedModelFileName();
        if (selected.isEmpty()) {
            addAssistantMessage(
                "Não há modelo local ativo para gerar o plano. "
                    + "Selecione um GGUF nos controles da aba IA.");
            return;
        }

        updateWorkflow(
            LaboratoryAiChatSessionStore.WorkflowState.PLANNING,
            contractId,
            "",
            "",
            "Planejador local em execução");

        final LaboratoryAiLocalPlannerProbe.Cancellation cancellation =
            new LaboratoryAiLocalPlannerProbe.Cancellation();
        activePlannerCancellation = cancellation;

        final LaboratoryAiExecutionStatus.Tracker status =
            new LaboratoryAiExecutionStatus.Tracker(
                contractId,
                snapshot -> runOnUi(() ->
                    renderPlannerStatus(snapshot)));

        setBusy(true);
        cancelButton.setText("CANCELAR PLANEJAMENTO");
        setLiveStatus("Preparando planejamento controlado…");

        worker.execute(() -> {
            try {
                LaboratoryAiLocalModelCatalog.Model model =
                    LaboratoryAiLocalModelCatalog.resolve(
                        activity.getFilesDir(), selected);

                LaboratoryAiLocalPlannerProbe.Result result =
                    LaboratoryAiLocalPlannerProbe.plan(
                        activity,
                        projectId,
                        contractId,
                        model.modelFile,
                        cancellation,
                        status);

                LaboratoryAiTaskContractStore.Contract after =
                    new LaboratoryAiTaskContractStore(
                        activity.getFilesDir(), projectId)
                        .read(contractId);
                if (after.claimed || after.resultRecorded) {
                    throw new IllegalStateException(
                        "Goal Lock foi alterado durante o planejamento");
                }

                persistPlannerHistory(status);
                runOnUi(() -> {
                    if (closed) return;
                    activePlannerCancellation = null;
                    setBusy(false);
                    renderPlannerResult(contractId, result);
                });
            } catch (Exception error) {
                LaboratoryAiExecutionStatus.Snapshot snapshot =
                    status.snapshot();
                if (!snapshot.terminal()) {
                    if (cancellation.isCancelled()) {
                        status.cancel(
                            "Planejamento cancelado pelo usuário");
                    } else {
                        status.fail(
                            String.valueOf(error.getMessage()));
                    }
                }
                persistPlannerHistory(status);
                final LaboratoryAiExecutionStatus.Snapshot terminal =
                    status.snapshot();
                runOnUi(() -> {
                    if (closed) return;
                    activePlannerCancellation = null;
                    setBusy(false);
                    LaboratoryAiPlannerExecutionDiagnostic.Result diagnosis =
                        LaboratoryAiPlannerExecutionDiagnostic.analyze(
                            terminal);
                    updateWorkflow(
                        terminal.state
                                == LaboratoryAiExecutionStatus.State.CANCELLED
                            ? LaboratoryAiChatSessionStore.WorkflowState.CANCELLED
                            : LaboratoryAiChatSessionStore.WorkflowState.FAILED,
                        contractId,
                        "",
                        "",
                        diagnosis.code.name());
                    addAssistantMessage(
                        (terminal.state
                            == LaboratoryAiExecutionStatus.State.CANCELLED
                                ? "Planejamento cancelado."
                                : "Não consegui produzir o plano.")
                            + "\nFase: " + phaseLabel(terminal.phase)
                            + "\nDiagnóstico: " + diagnosis.code.name()
                            + "\n" + diagnosis.explanation
                            + "\nPróxima verificação: "
                            + diagnosis.nextCheck
                            + plannerMetricSummary(terminal)
                            + "\nNenhuma ferramenta foi executada e o "
                            + "Goal Lock continua não consumido.");
                });
            }
        });
    }

    private void persistPlannerHistory(
            LaboratoryAiExecutionStatus.Tracker status) {
        try {
            new LaboratoryAiExecutionHistoryStore(
                activity.getFilesDir(), projectId)
                .saveExecution(status.history());
        } catch (Exception ignored) {
            // Diagnostic persistence cannot control the planner result.
        }
    }

    private void renderPlannerStatus(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        if (snapshot == null || snapshot.terminal() || !busy) return;

        StringBuilder out = new StringBuilder();
        out.append(phaseLabel(snapshot.phase))
            .append(" • ")
            .append(formatElapsed(snapshot.elapsedMs));

        if (snapshot.attempt > 0 && snapshot.maxAttempts > 0) {
            out.append(" • tentativa ")
                .append(snapshot.attempt)
                .append("/")
                .append(snapshot.maxAttempts);
        }

        if (snapshot.phase
                == LaboratoryAiExecutionStatus.Phase.MODEL_PROMPT
                && snapshot.promptTokens > 0) {
            out.append(" • prompt ")
                .append(snapshot.promptTokensProcessed)
                .append("/")
                .append(snapshot.promptTokens);
            if (snapshot.promptTokensPerSecond() > 0.0) {
                out.append(" • ")
                    .append(formatRate(
                        snapshot.promptTokensPerSecond()))
                    .append(" tok/s");
            }
            if (snapshot.estimatedRemainingMs > 0L) {
                out.append(" • ~")
                    .append(formatElapsed(
                        snapshot.estimatedRemainingMs))
                    .append(" restante");
            }
        } else if (snapshot.phase
                == LaboratoryAiExecutionStatus.Phase.MODEL_TOKENS
                && snapshot.maxGeneratedTokens > 0) {
            out.append(" • saída ")
                .append(snapshot.generatedTokens)
                .append("/")
                .append(snapshot.maxGeneratedTokens);
            if (snapshot.generatedTokensPerSecond() > 0.0) {
                out.append(" • ")
                    .append(formatRate(
                        snapshot.generatedTokensPerSecond()))
                    .append(" tok/s");
            }
        }

        setLiveStatus(out.toString());
        renderPlannerProgress(snapshot);
    }

    private void renderPlannerResult(
            String contractId,
            LaboratoryAiLocalPlannerProbe.Result result) {
        LaboratoryAiLlmTestPlanner.Result planner = result.planner;
        if (!planner.accepted || planner.plan == null) {
            StringBuilder rejected = new StringBuilder(
                "O modelo terminou o planejamento, mas o plano foi rejeitado "
                    + "pela validação determinística.");
            rejected.append("\nTentativas: ")
                .append(planner.attempts);
            for (LaboratoryAiTestPlanContract.Issue issue :
                    planner.issues) {
                rejected.append("\n• ")
                    .append(issue.code)
                    .append(" • passo ")
                    .append(issue.stepIndex)
                    .append(" • ")
                    .append(issue.field);
            }
            rejected.append(
                "\nNenhuma ferramenta foi executada e o Goal Lock "
                    + "continua não consumido.");
            updateWorkflow(
                LaboratoryAiChatSessionStore.WorkflowState.FAILED,
                contractId,
                "",
                "",
                "Plano rejeitado pela validação determinística");
            addAssistantMessage(rejected.toString());
            return;
        }

        StringBuilder accepted = new StringBuilder();
        accepted.append("Plano validado. Ainda não executei nenhuma ferramenta.")
            .append("\nPassos: ")
            .append(planner.plan.steps.size())
            .append(" • tentativa ")
            .append(planner.attempts)
            .append("\nModelo: ")
            .append(result.modelFileName);

        int index = 1;
        for (LaboratoryAiTestAgent.Step step :
                planner.plan.steps) {
            accepted.append("\n\n")
                .append(index++)
                .append(". ")
                .append(step.name)
                .append("\nFerramenta: ")
                .append(step.toolId)
                .append("\nRetorno esperado: ")
                .append(step.expectedFirstReturn);
        }
        accepted.append(
            "\n\nO Goal Lock permanece não consumido. "
                + "Preparar a Testadora também não executa o plano.");
        latestValidatedPlan = planner.plan;
        updateWorkflow(
            LaboratoryAiChatSessionStore.WorkflowState.PLAN_READY,
            contractId,
            "",
            "",
            "Plano validado; Testadora ainda não preparada");
        addAssistantMessage(accepted.toString());
    }

    private void prepareTestAgentInline(
            String contractId,
            LaboratoryAiTestAgent.Plan plan) {
        if (closed || busy || plan == null) return;

        setBusy(true);
        cancelButton.setVisibility(GONE);
        setLiveStatus("Preparando cenário imutável para revisão…");

        worker.execute(() -> {
            try {
                LaboratoryAiValidatedPlanExecutionGate.Prepared prepared =
                    LaboratoryAiValidatedPlanExecutionGate.prepare(
                        activity,
                        projectId,
                        contractId,
                        plan);
                runOnUi(() -> {
                    if (closed) return;
                    setBusy(false);
                    updateWorkflow(
                        LaboratoryAiChatSessionStore.WorkflowState.TEST_PREPARED,
                        contractId,
                        prepared.scenarioId,
                        "",
                        "Cenário imutável preparado; execução aguarda confirmação");
                    addAssistantMessage(
                        "Testadora preparada, mas ainda não executada."
                            + "\nCenário: " + prepared.scenarioId
                            + "\nPassos: " + prepared.stepCount
                            + "\nStop on failure: "
                            + (prepared.stopOnFailure ? "SIM" : "NÃO")
                            + "\n\nExecutar agora consumirá o Goal Lock "
                            + "de uso único e permitirá somente as ferramentas "
                            + "que você aprovou para esta tarefa.");
                });
            } catch (Exception error) {
                runOnUi(() -> {
                    if (closed) return;
                    setBusy(false);
                    updateWorkflow(
                        LaboratoryAiChatSessionStore.WorkflowState.FAILED,
                        contractId,
                        "",
                        "",
                        "Falha ao preparar cenário da Testadora");
                    addAssistantMessage(
                        "Não consegui preparar a Testadora. "
                            + "Nada foi executado e o Goal Lock não foi consumido."
                            + "\n" + String.valueOf(error.getMessage()));
                });
            }
        });
    }

    private void confirmAndExecutePrepared(
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared) {
        new AlertDialog.Builder(activity)
            .setTitle("Executar teste controlado?")
            .setMessage(
                "Esta confirmação inicia a Testadora determinística e consome "
                    + "o Goal Lock de uso único. Somente as ferramentas "
                    + "explicitamente aprovadas para a tarefa poderão ser usadas.\n\n"
                    + "Cenário: " + prepared.scenarioId
                    + "\nPassos: " + prepared.stepCount)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton(
                "EXECUTAR TESTE",
                (dialog, which) -> executePreparedInline(prepared))
            .show();
    }

    private void executePreparedInline(
            LaboratoryAiValidatedPlanExecutionGate.Prepared prepared) {
        if (closed || busy) return;

        updateWorkflow(
            LaboratoryAiChatSessionStore.WorkflowState.TEST_RUNNING,
            prepared.contractId,
            prepared.scenarioId,
            "",
            "Testadora determinística em execução");

        final LaboratoryAiTestAgent.Control control =
            new LaboratoryAiTestAgent.Control();
        activeTestControl = control;

        setBusy(true);
        cancelButton.setText("CANCELAR TESTE");
        setLiveStatus(
            "Testadora executando cenário controlado…");

        worker.execute(() -> {
            try {
                LaboratoryAiValidatedPlanExecutionGate.Execution execution =
                    LaboratoryAiValidatedPlanExecutionGate.executePrepared(
                        activity,
                        projectId,
                        prepared,
                        control,
                        new LaboratoryAiTestAgent.Observer() {
                            @Override
                            public void onAdmitted(
                                    String sessionId,
                                    int plannedSteps) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        setLiveStatus(
                                            "Testadora admitida • "
                                                + plannedSteps
                                                + " passo(s)");
                                        renderTestProgress(
                                            0,
                                            plannedSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }

                            @Override
                            public void onStepStarted(
                                    int stepIndex,
                                    int totalSteps,
                                    String stepName,
                                    String toolId) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        setLiveStatus(
                                            "Testadora • passo "
                                                + stepIndex + "/"
                                                + totalSteps
                                                + " • " + toolId
                                                + " • executando");
                                        renderTestProgress(
                                            Math.max(0, stepIndex - 1),
                                            totalSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }

                            @Override
                            public void onStepFinished(
                                    int stepIndex,
                                    int totalSteps,
                                    LaboratoryAiTestAgent.StepEvidence evidence) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        setLiveStatus(
                                            "Testadora • passo "
                                                + stepIndex + "/"
                                                + totalSteps
                                                + " • " + evidence.toolId
                                                + " • "
                                                + (evidence.passed
                                                    ? "PASSOU"
                                                    : "FALHOU")
                                                + " • "
                                                + evidence.durationMs
                                                + " ms");
                                        renderTestProgress(
                                            stepIndex,
                                            totalSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }

                            @Override
                            public void onPaused(
                                    int completedSteps,
                                    int totalSteps) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        updateWorkflow(
                                            LaboratoryAiChatSessionStore
                                                .WorkflowState.TEST_PAUSED,
                                            prepared.contractId,
                                            prepared.scenarioId,
                                            "",
                                            "Pausada após "
                                                + completedSteps
                                                + "/" + totalSteps
                                                + " passo(s)");
                                        setLiveStatus(
                                            "Testadora pausada • "
                                                + completedSteps + "/"
                                                + totalSteps
                                                + " passo(s) concluído(s)");
                                        renderTestProgress(
                                            completedSteps,
                                            totalSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }

                            @Override
                            public void onResumed(
                                    int completedSteps,
                                    int totalSteps) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        updateWorkflow(
                                            LaboratoryAiChatSessionStore
                                                .WorkflowState.TEST_RUNNING,
                                            prepared.contractId,
                                            prepared.scenarioId,
                                            "",
                                            "Testadora retomada");
                                        setLiveStatus(
                                            "Testadora retomada • "
                                                + completedSteps + "/"
                                                + totalSteps
                                                + " passo(s) concluído(s)");
                                        renderTestProgress(
                                            completedSteps,
                                            totalSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }

                            @Override
                            public void onFinished(
                                    LaboratoryAiTestAgent.Report report) {
                                runOnUi(() -> {
                                    if (!closed && busy) {
                                        setLiveStatus(
                                            "Finalizando relatório • "
                                                + report.executedSteps
                                                + "/"
                                                + report.plannedSteps
                                                + " passo(s)");
                                        renderTestProgress(
                                            report.executedSteps,
                                            report.plannedSteps);
                                        renderTestBudget(control.snapshot());
                                    }
                                });
                            }
                        });
                LaboratoryAiSessionStore.Summary finalUsage =
                    findSessionSummary(execution.sessionId);
                runOnUi(() -> {
                    if (closed) return;
                    activeTestControl = null;
                    setBusy(false);
                    LaboratoryAiChatSessionStore.WorkflowState terminalState;
                    if ("CANCELLED".equals(execution.status)) {
                        terminalState =
                            LaboratoryAiChatSessionStore.WorkflowState.CANCELLED;
                    } else if ("PASS".equals(execution.status)) {
                        terminalState =
                            LaboratoryAiChatSessionStore.WorkflowState.COMPLETED;
                    } else {
                        terminalState =
                            LaboratoryAiChatSessionStore.WorkflowState.FAILED;
                    }
                    updateWorkflow(
                        terminalState,
                        execution.contractId,
                        execution.scenarioId,
                        execution.reportId,
                        execution.status
                            + (execution.terminalReason.isEmpty()
                                ? ""
                                : " • " + execution.terminalReason));
                    addAssistantMessage(
                        "Teste concluído."
                            + "\nStatus: " + execution.status
                            + "\nPassos: " + execution.executedSteps
                            + "/" + execution.plannedSteps
                            + "\nPassaram: " + execution.passed
                            + " • Falharam: " + execution.failed
                            + "\nDuração: "
                            + formatElapsed(execution.durationMs)
                            + (execution.terminalReason.isEmpty()
                                ? ""
                                : "\nMotivo terminal: "
                                    + execution.terminalReason)
                            + "\nRelatório: " + execution.reportId
                            + "\nSessão: " + execution.sessionId
                            + "\nGoal Lock consumido: "
                            + (execution.goalLockClaimed ? "SIM" : "NÃO")
                            + "\nResultado registrado: "
                            + (execution.resultRecorded ? "SIM" : "NÃO")
                            + (finalUsage == null
                                ? ""
                                : "\nUso final: "
                                    + finalUsage.invocationsUsed
                                    + "/" + finalUsage.maxInvocations
                                    + " chamada(s) • "
                                    + formatBytes(finalUsage.inputBytesUsed)
                                    + "/"
                                    + formatBytes(
                                        finalUsage.maxTotalInputBytes)
                                    + " de entrada"));
                    addActionButton(
                        "ABRIR RELATÓRIOS DA TESTADORA",
                        () -> activity.startActivity(
                            new Intent(
                                activity,
                                LaboratoryAiTestAgentReportsActivity.class)));
                });
            } catch (Exception error) {
                runOnUi(() -> {
                    if (closed) return;
                    activeTestControl = null;
                    setBusy(false);
                    updateWorkflow(
                        control.isCancellationRequested()
                            ? LaboratoryAiChatSessionStore.WorkflowState.CANCELLED
                            : LaboratoryAiChatSessionStore.WorkflowState.FAILED,
                        prepared.contractId,
                        prepared.scenarioId,
                        "",
                        String.valueOf(error.getMessage()));
                    addAssistantMessage(
                        "A Testadora não concluiu o cenário."
                            + "\n" + String.valueOf(error.getMessage())
                            + "\nConsulte os relatórios e o diagnóstico "
                            + "antes de tentar novamente.");
                    addActionButton(
                        "ABRIR RELATÓRIOS DA TESTADORA",
                        () -> activity.startActivity(
                            new Intent(
                                activity,
                                LaboratoryAiTestAgentReportsActivity.class)));
                });
            }
        });
    }

    private LaboratoryAiSessionStore.Summary findSessionSummary(
            String sessionId) {
        if (sessionId == null || sessionId.isEmpty()) return null;
        try {
            for (LaboratoryAiSessionStore.Summary summary :
                    new LaboratoryAiSessionStore(
                        activity.getFilesDir(), projectId).list()) {
                if (sessionId.equals(summary.sessionId)) {
                    return summary;
                }
            }
        } catch (Exception ignored) {
            // Usage display is diagnostic-only and cannot alter execution.
        }
        return null;
    }

    private static String plannerMetricSummary(
            LaboratoryAiExecutionStatus.Snapshot snapshot) {
        StringBuilder out = new StringBuilder();
        if (snapshot.contextSetupMs > 0L) {
            out.append("\nContexto: ")
                .append(snapshot.contextSetupMs)
                .append(" ms");
        }
        if (snapshot.promptTokens > 0) {
            out.append("\nPrompt: ")
                .append(snapshot.promptTokensProcessed)
                .append("/")
                .append(snapshot.promptTokens)
                .append(" tokens • ")
                .append(snapshot.promptEvalMs)
                .append(" ms");
        }
        if (snapshot.maxGeneratedTokens > 0) {
            out.append("\nGeração: ")
                .append(snapshot.generatedTokens)
                .append("/")
                .append(snapshot.maxGeneratedTokens)
                .append(" tokens • ")
                .append(snapshot.tokenGenerationMs)
                .append(" ms");
        }
        return out.toString();
    }

    private static String phaseLabel(
            LaboratoryAiExecutionStatus.Phase phase) {
        if (phase == null) return "Etapa desconhecida";
        switch (phase) {
            case PREPARING:
                return "Preparando";
            case MODEL_ADMISSION:
                return "Validando modelo";
            case PREFLIGHT:
                return "Verificando dispositivo";
            case MODEL_OPEN:
                return "Abrindo modelo";
            case RUNTIME_METADATA:
                return "Lendo runtime";
            case PLANNING:
                return "Montando plano";
            case MODEL_CONTEXT:
                return "Preparando contexto";
            case MODEL_PROMPT:
                return "Processando prompt";
            case MODEL_TOKENS:
                return "Gerando plano";
            case VALIDATING:
                return "Validando plano";
            case COMPLETED:
                return "Concluído";
            default:
                return phase.name();
        }
    }

    private String buildConversationPrompt(
            String latestMessage,
            LaboratoryAiChatRouter.Kind kind) {
        final String modelOnlyRule =
            "Você NÃO recebeu ferramentas, não executou ações, não alterou "
                + "arquivos e não deve afirmar que verificou ou modificou o "
                + "estado real do aplicativo. ";

        final String modeInstruction;
        if (kind == LaboratoryAiChatRouter.Kind.ANALYSIS) {
            modeInstruction =
                "Esta chamada é de ANÁLISE/VIABILIDADE. Você pode avaliar "
                    + "se uma ideia ou processo parece viável, montar um plano "
                    + "conceitual, explicitar hipóteses, riscos, dependências e "
                    + "critérios de validação usando somente o contexto da "
                    + "conversa. Se a conclusão depender de inspecionar arquivos, "
                    + "executar testes, pesquisar dados ou medir o app real, diga "
                    + "claramente o que falta e que essa verificação exige o "
                    + "fluxo controlado de ação. Não crie Goal Lock nem finja "
                    + "que uma verificação prática aconteceu. ";
        } else {
            modeInstruction =
                "Esta chamada é somente conversa. Se o usuário pedir uma ação, "
                    + "explique brevemente que ações usam o fluxo controlado "
                    + "do app. ";
        }

        final String instruction =
            "Você é a CAFEÍNA, assistente local do aplicativo CAFEÍNA. "
                + "Responda em português brasileiro, de forma natural e clara. "
                + modelOnlyRule
                + modeInstruction
                + "\n\n";

        StringBuilder conversation = new StringBuilder();
        synchronized (transcript) {
            int start = Math.max(
                0,
                transcript.size() - MAX_TRANSCRIPT_ENTRIES);
            for (int i = start; i < transcript.size(); i++) {
                ChatEntry entry = transcript.get(i);
                conversation.append(
                    entry.user ? "Usuário: " : "CAFEÍNA: ")
                    .append(entry.text)
                    .append('\n');
            }
            if (transcript.isEmpty()
                    || !transcript.get(transcript.size() - 1).user
                    || !transcript.get(transcript.size() - 1).text
                        .equals(latestMessage)) {
                conversation.append("Usuário: ")
                    .append(latestMessage)
                    .append('\n');
            }
        }
        conversation.append("CAFEÍNA:");

        int conversationBudget = Math.max(
            512,
            MAX_TRANSCRIPT_CHARS - instruction.length());
        String body = conversation.toString();
        if (body.length() > conversationBudget) {
            body = body.substring(body.length() - conversationBudget);
            int firstBreak = body.indexOf('\n');
            if (firstBreak >= 0 && firstBreak + 1 < body.length()) {
                body = body.substring(firstBreak + 1);
            }
        }
        return instruction + body;
    }

    private void pauseActiveTest() {
        LaboratoryAiTestAgent.Control control = activeTestControl;
        if (control == null || closed) return;
        control.pause();
        setLiveStatus(
            "Pausa solicitada • aguardando o próximo ponto seguro entre passos…");
        refreshCurrentActionStatus();
    }

    private void resumeActiveTest() {
        LaboratoryAiTestAgent.Control control = activeTestControl;
        if (control == null || closed) return;
        control.resume();
        setLiveStatus("Retomada solicitada à Testadora…");
        refreshCurrentActionStatus();
    }

    private void cancelActiveResponse() {
        LaboratoryAiLocalPlannerProbe.Cancellation planner =
            activePlannerCancellation;
        if (planner != null) {
            planner.cancel();
            setLiveStatus("Cancelamento solicitado ao planejador…");
            cancelButton.setEnabled(false);
            return;
        }

        LaboratoryAiTestAgent.Control testControl =
            activeTestControl;
        if (testControl != null) {
            testControl.cancel();
            setLiveStatus("Cancelamento solicitado à Testadora…");
            cancelButton.setEnabled(false);
            return;
        }

        LaboratoryAiLlamaCppBackend backend = activeBackend;
        if (backend != null) {
            backend.cancelGeneration();
            setLiveStatus("Cancelamento solicitado ao modelo local…");
            cancelButton.setEnabled(false);
        }
    }

    private void updatePhaseStatus(int phase) {
        String label;
        switch (phase) {
            case LlamaBridge.GENERATION_PHASE_CONTEXT:
                label = "Preparando contexto…";
                break;
            case LlamaBridge.GENERATION_PHASE_PROMPT:
                label = "Processando mensagem…";
                break;
            case LlamaBridge.GENERATION_PHASE_TOKENS:
                label = "Gerando resposta…";
                break;
            default:
                return;
        }
        runOnUi(() -> {
            if (!closed && busy) setLiveStatus(label);
        });
    }

    private void updateMetricStatus(LlamaBridge.GenerationMetrics metrics) {
        if (metrics == null) return;
        String rendered = null;
        if (metrics.phase == LlamaBridge.GENERATION_PHASE_CONTEXT) {
            rendered = "Preparando contexto • "
                + formatElapsed(metrics.contextSetupMs);
        } else if (metrics.phase
                == LlamaBridge.GENERATION_PHASE_PROMPT) {
            StringBuilder out = new StringBuilder("Processando mensagem");
            if (metrics.promptTokens > 0) {
                out.append(" • ")
                    .append(metrics.promptTokensProcessed)
                    .append("/")
                    .append(metrics.promptTokens)
                    .append(" tokens");
                double rate = rate(
                    metrics.promptTokensProcessed,
                    metrics.promptEvalMs);
                if (rate > 0.0) {
                    out.append(" • ")
                        .append(formatRate(rate))
                        .append(" tok/s");
                }
            }
            out.append(" • ")
                .append(formatElapsed(metrics.promptEvalMs));
            rendered = out.toString();
        } else if (metrics.phase
                == LlamaBridge.GENERATION_PHASE_TOKENS) {
            StringBuilder out = new StringBuilder("Gerando resposta");
            out.append(" • ")
                .append(metrics.generatedTokens)
                .append("/")
                .append(metrics.maxGeneratedTokens)
                .append(" tokens");
            double rate = rate(
                metrics.generatedTokens,
                metrics.tokenGenerationMs);
            if (rate > 0.0) {
                out.append(" • ")
                    .append(formatRate(rate))
                    .append(" tok/s");
            }
            out.append(" • ")
                .append(formatElapsed(metrics.tokenGenerationMs));
            rendered = out.toString();
        }

        final String statusText = rendered;
        if (statusText == null) return;
        runOnUi(() -> {
            if (!closed && busy) setLiveStatus(statusText);
        });
    }

    private void setBusy(boolean value) {
        busy = value;
        sendButton.setEnabled(!value);
        input.setEnabled(!value);
        cancelButton.setVisibility(value ? VISIBLE : GONE);
        cancelButton.setEnabled(value);
        refreshActionDiagnosticButton();
        if (!value) {
            cancelButton.setText("CANCELAR RESPOSTA");
            hideLiveStatus();
        }
    }

    private void setLiveStatus(String value) {
        liveStatus.setText(value == null ? "" : value);
        liveStatus.setVisibility(VISIBLE);
        refreshCurrentActionStatus();
    }

    private void hideLiveStatus() {
        liveStatus.setText("");
        liveStatus.setVisibility(GONE);
        refreshCurrentActionStatus();
    }

    private void addUserMessage(
            String value,
            boolean modelContext) {
        String clean = boundedChatText(value);
        if (clean.isEmpty()) return;
        addBubble(clean, true);
        if (modelContext) remember(true, clean);
        persistVisibleEntry(
            LaboratoryAiChatSessionStore.Role.USER,
            clean,
            modelContext);
    }

    private void addAssistantMessage(String value) {
        String clean = boundedChatText(value);
        if (clean.isEmpty()) return;
        addBubble(clean, false);
        persistVisibleEntry(
            LaboratoryAiChatSessionStore.Role.ASSISTANT,
            clean,
            false);
    }

    private void addAssistantConversationMessage(String value) {
        String clean = boundedChatText(value);
        if (clean.isEmpty()) return;
        addBubble(clean, false);
        remember(false, clean);
        persistVisibleEntry(
            LaboratoryAiChatSessionStore.Role.ASSISTANT,
            clean,
            true);
    }

    private void addBubble(String value, boolean user) {
        LinearLayout row = new LinearLayout(activity);
        row.setGravity(user ? Gravity.END : Gravity.START);

        TextView bubble = text(
            value == null ? "" : value,
            14,
            FG,
            false);
        bubble.setMaxWidth(dp(330));
        bubble.setPadding(dp(12), dp(9), dp(12), dp(9));
        GradientDrawable background = new GradientDrawable();
        background.setColor(user ? USER_PANEL : PANEL);
        background.setCornerRadius(dp(14));
        bubble.setBackground(background);
        bubble.setTextIsSelectable(true);

        row.addView(
            bubble,
            new LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        LayoutParams rowParams = matchWrap();
        rowParams.setMargins(0, dp(4), 0, dp(4));
        messages.addView(row, rowParams);
        scrollToBottom();
    }

    private void addActionButton(String label, Runnable action) {
        Button button = button(label, PANEL);
        button.setAllCaps(false);
        button.setOnClickListener(v -> {
            if (action != null) action.run();
        });
        LayoutParams params = matchWrap();
        params.setMargins(dp(18), dp(3), dp(18), dp(3));
        messages.addView(button, params);
        scrollToBottom();
    }

    private void remember(boolean user, String value) {
        if (value == null || value.trim().isEmpty()) return;
        synchronized (transcript) {
            transcript.add(new ChatEntry(user, value.trim()));
            while (transcript.size() > MAX_TRANSCRIPT_ENTRIES) {
                transcript.remove(0);
            }
        }
    }

    private void scrollToBottom() {
        messageScroll.post(() ->
            messageScroll.fullScroll(View.FOCUS_DOWN));
    }

    private String selectedModelFileName() {
        return activity.getSharedPreferences(
            MODEL_PREFS, Activity.MODE_PRIVATE)
            .getString(ACTIVE_MODEL, "");
    }

    private void runOnUi(Runnable action) {
        activity.runOnUiThread(() -> {
            if (!activity.isFinishing()
                    && !activity.isDestroyed()) {
                action.run();
            }
        });
    }

    private TextView text(
            String value,
            int sp,
            int color,
            boolean bold) {
        TextView view = new TextView(activity);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        if (bold) {
            view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        }
        return view;
    }

    private Button button(String label, int color) {
        Button result = new Button(activity);
        result.setText(label);
        result.setTextColor(FG);
        result.setTextSize(12);
        result.setBackgroundTintList(
            ColorStateList.valueOf(color));
        return result;
    }

    private LayoutParams matchWrap() {
        return new LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(
            value * getResources().getDisplayMetrics().density);
    }

    private static double rate(int tokens, long elapsedMs) {
        if (tokens <= 0 || elapsedMs <= 0L) return 0.0;
        return tokens * 1000.0 / elapsedMs;
    }

    private static String formatRate(double value) {
        if (Double.isNaN(value)
                || Double.isInfinite(value)
                || value <= 0.0) {
            return "0.0";
        }
        return String.format(Locale.ROOT, "%.1f", value);
    }

    private static String formatElapsed(long elapsedMs) {
        long safe = Math.max(0L, elapsedMs);
        if (safe < 1000L) return safe + " ms";
        long seconds = safe / 1000L;
        long minutes = seconds / 60L;
        long remainder = seconds % 60L;
        if (minutes == 0L) return remainder + " s";
        return minutes + " min " + remainder + " s";
    }
}
