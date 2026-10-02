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
 * Conversation is model-only and receives no tool handles. Obvious action
 * requests are diverted into Goal Lock + per-task permission review before the
 * existing controlled planner is opened.
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
    private final List<ChatEntry> transcript = new ArrayList<>();

    private final ScrollView messageScroll;
    private final LinearLayout messages;
    private final EditText input;
    private final Button sendButton;
    private final Button cancelButton;
    private final TextView liveStatus;

    private volatile LaboratoryAiLlamaCppBackend activeBackend;
    private volatile boolean busy;
    private volatile boolean closed;

    public LaboratoryAiChatPanel(Activity activity, String projectId) {
        super(activity);
        if (activity == null || projectId == null) {
            throw new IllegalArgumentException("chat panel context missing");
        }
        this.activity = activity;
        this.projectId = projectId;

        setOrientation(VERTICAL);
        setBackgroundColor(BG);

        TextView heading = text("CONVERSA COM A CAFEÍNA", 15, FG, true);
        heading.setPadding(0, 0, 0, dp(6));
        addView(heading, matchWrap());

        TextView note = text(
            "Mensagens comuns vão direto ao modelo local. Pedidos de ação entram "
                + "no Goal Lock e nas permissões antes de qualquer execução.",
            12,
            MUTED,
            false);
        note.setPadding(0, 0, 0, dp(8));
        addView(note, matchWrap());

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

        addAssistantMessage(
            "Pode falar comigo normalmente. Se você pedir uma ação no app, "
                + "eu separo conversa de execução e peço as permissões da tarefa.");
    }

    public void close() {
        if (closed) return;
        closed = true;
        cancelActiveResponse();
        worker.shutdownNow();
    }

    private void sendCurrent() {
        if (closed || busy) return;
        String message = input.getText().toString().trim();
        if (message.isEmpty()) return;
        input.setText("");

        LaboratoryAiChatRouter.Route route =
            LaboratoryAiChatRouter.route(message);
        boolean conversation =
            route.kind == LaboratoryAiChatRouter.Kind.CONVERSATION;
        addUserMessage(message, conversation);

        if (conversation) {
            runConversation(message);
        } else {
            handleAction(message, route);
        }
    }

    private void runConversation(String message) {
        final String selected = selectedModelFileName();
        if (selected.isEmpty()) {
            addAssistantMessage(
                "Ainda não há modelo local ativo. Selecione um GGUF nos "
                    + "controles logo abaixo do chat e envie a mensagem novamente.");
            return;
        }

        setBusy(true);
        setLiveStatus("Preparando modelo local…");
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
                        buildConversationPrompt(message),
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
                        addAssistantMessage(clean);
                        remember(false, clean);
                    }
                    setBusy(false);
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
        addAssistantMessage(
            "Entendi isso como um pedido de ação. Não executei nada. "
                + "Vou manter esse pedido fora da conversa livre e preparar "
                + "Goal Lock + permissões da tarefa primeiro.");

        worker.execute(() -> {
            try {
                List<LaboratoryAiToolController.Tool> available =
                    LaboratoryAiToolController.listAvailable(
                        activity, projectId);
                runOnUi(() -> renderActionPreparation(
                    message, route.modeHint, available));
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

        if (safe.isEmpty()) {
            addAssistantMessage(
                "Nenhuma ferramenta STABLE está liberada para a IA neste "
                    + "projeto. O pedido continua intacto e nada foi executado.");
            addActionButton(
                "REVISAR PERMISSÕES DA IA",
                () -> activity.startActivity(
                    new Intent(
                        activity,
                        LaboratoryAiPermissionsActivity.class)));
            return;
        }

        StringBuilder names = new StringBuilder();
        for (LaboratoryAiToolController.Tool tool : safe) {
            if (names.length() > 0) names.append(", ");
            names.append(tool.toolId);
        }
        addAssistantMessage(
            "Ferramentas disponíveis para este pedido: " + names
                + ". Você escolhe explicitamente quais entram no Goal Lock. "
                + "Orçamento inicial: " + TASK_MAX_INVOCATIONS
                + " chamadas • " + (TASK_MAX_TOTAL_INPUT_BYTES / 1024)
                + " KiB • " + (TASK_MAX_SESSION_MS / 60_000L) + " min.");
        addActionButton(
            "PREPARAR GOAL LOCK",
            () -> showTaskPermissionDialog(message, modeHint, safe));
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
            List<LaboratoryAiToolController.Tool> tools) {
        if (tools == null || tools.isEmpty()) return;

        String[] labels = new String[tools.size()];
        boolean[] checked = new boolean[tools.size()];
        for (int i = 0; i < tools.size(); i++) {
            LaboratoryAiToolController.Tool tool = tools.get(i);
            labels[i] = tool.toolId + " • " + tool.version;
        }

        String modeLabel =
            modeHint == LaboratoryAiChatRouter.ModeHint.LEARNING
                ? "APRENDIZADO"
                : "CRIAÇÃO";

        AlertDialog dialog = new AlertDialog.Builder(activity)
            .setTitle("Permissões desta tarefa • " + modeLabel)
            .setMessage(
                "Escolha somente as ferramentas que esta tarefa poderá usar.\n\n"
                    + "Orçamento inicial: "
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
                    showTaskPermissionDialog(message, other, tools);
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
                    createGoalLock(message, modeHint, selected);
                });
        });
        dialog.show();
    }

    private void createGoalLock(
            String message,
            LaboratoryAiChatRouter.ModeHint modeHint,
            List<String> selectedToolIds) {
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
                    addAssistantMessage(
                        "Goal Lock criado. Objetivo travado em "
                            + contract.mode.name()
                            + ", com " + contract.allowedToolIds.size()
                            + " ferramenta(s). Nada foi executado.\n"
                            + "Contrato: " + contract.contractId);
                    addActionButton(
                        "GERAR PLANO • NÃO EXECUTAR",
                        () -> activity.startActivity(
                            new Intent(
                                activity,
                                LaboratoryAiLocalPlannerActivity.class)));
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

    private String buildConversationPrompt(String latestMessage) {
        final String instruction =
            "Você é a CAFEÍNA, assistente local do aplicativo CAFEÍNA. "
                + "Responda em português brasileiro, de forma natural e clara. "
                + "Esta chamada é somente conversa: você NÃO recebeu ferramentas, "
                + "não executou ações, não alterou arquivos e não deve afirmar que "
                + "fez algo no aplicativo. Se o usuário pedir uma ação, explique "
                + "brevemente que ações usam o fluxo controlado do app.\n\n";

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

    private void cancelActiveResponse() {
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
        if (!value) hideLiveStatus();
    }

    private void setLiveStatus(String value) {
        liveStatus.setText(value == null ? "" : value);
        liveStatus.setVisibility(VISIBLE);
    }

    private void hideLiveStatus() {
        liveStatus.setText("");
        liveStatus.setVisibility(GONE);
    }

    private void addUserMessage(String value, boolean remember) {
        addBubble(value, true);
        if (remember) remember(true, value);
    }

    private void addAssistantMessage(String value) {
        addBubble(value, false);
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
