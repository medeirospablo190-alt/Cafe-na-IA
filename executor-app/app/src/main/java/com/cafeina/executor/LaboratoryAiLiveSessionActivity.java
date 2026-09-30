package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private host-only dashboard for sessions alive in the current process.
 * It never receives AiHandle and never executes tools itself.
 */
public final class LaboratoryAiLiveSessionActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);
    private static final int PAUSE_COLOR = Color.rgb(148, 111, 47);
    private static final int CANCEL_COLOR = Color.rgb(126, 56, 61);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable tick = () -> refresh(false);

    private TextView feedback;
    private LinearLayout entries;
    private String projectId;
    private boolean refreshRunning;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR", ACCENT);
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("SESSÕES DA IA • AO VIVO", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Controles exclusivos do usuário/host. A IA não recebe acesso a "
                + "pausar, continuar, finalizar ou cancelar a própria sessão.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando sessões vivas…", 14, MUTED, false);
        feedback.setPadding(0, dp(12), 0, dp(8));
        root.addView(feedback, matchWrap());

        LinearLayout globalActions = new LinearLayout(this);
        globalActions.setOrientation(LinearLayout.HORIZONTAL);
        Button pauseAll = button("PAUSAR TODAS", PAUSE_COLOR);
        pauseAll.setOnClickListener(v -> pauseAll());
        globalActions.addView(pauseAll, actionParams());
        Button resumeAll = button("CONTINUAR TODAS", ACCENT);
        resumeAll.setOnClickListener(v -> resumeAll());
        globalActions.addView(resumeAll, actionParams());
        root.addView(globalActions, matchWrap());

        Button cancelAll = button("CANCELAR TODAS", CANCEL_COLOR);
        cancelAll.setOnClickListener(v -> confirmCancelAll());
        LinearLayout.LayoutParams cancelAllParams = matchWrap();
        cancelAllParams.setMargins(0, dp(6), 0, dp(8));
        root.addView(cancelAll, cancelAllParams);

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh(true);
    }

    @Override
    protected void onPause() {
        main.removeCallbacks(tick);
        super.onPause();
    }

    private void refresh(boolean immediate) {
        if (!alive()) return;
        if (refreshRunning) {
            scheduleNext();
            return;
        }
        refreshRunning = true;
        if (immediate) feedback.setText("Atualizando sessões vivas…");
        io.execute(() -> {
            List<LaboratoryAiLiveSessionRegistry.Info> sessions;
            Exception problem = null;
            try {
                sessions = LaboratoryAiLiveSessionRegistry.list(projectId);
            } catch (Exception error) {
                sessions = java.util.Collections.emptyList();
                problem = error;
            }
            final List<LaboratoryAiLiveSessionRegistry.Info> result = sessions;
            final Exception failure = problem;
            runOnUiThread(() -> {
                refreshRunning = false;
                if (!alive()) return;
                if (failure != null) {
                    feedback.setText("Falha ao consultar sessões: "
                        + failure.getMessage());
                    entries.removeAllViews();
                } else {
                    render(result);
                }
                scheduleNext();
            });
        });
    }

    private void scheduleNext() {
        main.removeCallbacks(tick);
        if (alive() && !isFinishing()) main.postDelayed(tick, 1000L);
    }

    private void render(List<LaboratoryAiLiveSessionRegistry.Info> sessions) {
        entries.removeAllViews();
        feedback.setText(sessions.size() + " sessão(ões) viva(s) neste projeto");

        if (sessions.isEmpty()) {
            entries.addView(text(
                "Nenhuma sessão da IA está viva neste processo. "
                    + "Sessões interrompidas aparecem na área de recuperação.",
                14, MUTED, false), matchWrap());
            return;
        }

        for (LaboratoryAiLiveSessionRegistry.Info info : sessions) {
            LaboratoryAiSessionController.Snapshot snapshot = info.snapshot;
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            String stateLabel = snapshot.state.name();
            TextView details = text(
                "SESSÃO • " + stateLabel
                    + "\nID: " + info.sessionId
                    + "\nFerramentas: " + info.allowedToolIds
                    + "\nChamadas: " + snapshot.invocationsUsed
                    + " usadas • " + snapshot.invocationsRemaining + " restantes"
                    + "\nEntrada: " + snapshot.inputBytesUsed
                    + " bytes usados • " + snapshot.inputBytesRemaining + " restantes"
                    + "\nTempo: " + snapshot.elapsedMs
                    + " ms decorridos • " + snapshot.remainingMs + " ms restantes"
                    + "\nWorker ativo: "
                    + (snapshot.hasActiveInvocation ? "SIM" : "NÃO"),
                13, FG, true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            LinearLayout actions = new LinearLayout(this);
            actions.setOrientation(LinearLayout.HORIZONTAL);

            if (snapshot.state == LaboratoryAiSessionController.State.ACTIVE) {
                Button pause = button("PAUSAR", PAUSE_COLOR);
                pause.setOnClickListener(v -> pause(info.sessionId));
                actions.addView(pause, actionParams());
            } else if (snapshot.state == LaboratoryAiSessionController.State.PAUSED) {
                Button resume = button("CONTINUAR", ACCENT);
                resume.setOnClickListener(v -> resume(info.sessionId));
                actions.addView(resume, actionParams());
            }

            Button finish = button("FINALIZAR", Color.rgb(55, 116, 82));
            finish.setOnClickListener(v -> confirmComplete(info.sessionId));
            actions.addView(finish, actionParams());

            Button cancel = button("CANCELAR", CANCEL_COLOR);
            cancel.setOnClickListener(v -> confirmCancel(info.sessionId));
            actions.addView(cancel, actionParams());

            LinearLayout.LayoutParams actionRow = matchWrap();
            actionRow.setMargins(0, dp(8), 0, 0);
            card.addView(actions, actionRow);

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }
    }

    private void pauseAll() {
        feedback.setText("Pausando sessões do projeto…");
        io.execute(() -> {
            LaboratoryAiLiveSessionRegistry.BulkResult result =
                LaboratoryAiLiveSessionRegistry.pauseAll(projectId);
            showBulkResult("Pausa global", result);
        });
    }

    private void resumeAll() {
        feedback.setText("Continuando sessões pausadas…");
        io.execute(() -> {
            LaboratoryAiLiveSessionRegistry.BulkResult result =
                LaboratoryAiLiveSessionRegistry.resumeAll(projectId);
            showBulkResult("Retomada global", result);
        });
    }

    private void confirmCancelAll() {
        new AlertDialog.Builder(this)
            .setTitle("Cancelar todas as sessões")
            .setMessage("Cancelar todas as sessões vivas deste projeto? "
                + "Workers ativos serão cancelados e o histórico será preservado.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("CANCELAR TODAS", (dialog, which) -> cancelAll())
            .show();
    }

    private void cancelAll() {
        feedback.setText("Cancelando todas as sessões…");
        io.execute(() -> {
            LaboratoryAiLiveSessionRegistry.BulkResult result =
                LaboratoryAiLiveSessionRegistry.cancelAll(projectId);
            showBulkResult("Cancelamento global", result);
        });
    }

    private void showBulkResult(String label,
            LaboratoryAiLiveSessionRegistry.BulkResult result) {
        runOnUiThread(() -> {
            if (!alive()) return;
            if (result.attempted == 0) {
                feedback.setText(label + ": nenhuma sessão aplicável.");
            } else if (result.complete()) {
                feedback.setText(label + ": " + result.changed
                    + " sessão(ões) atualizada(s).");
            } else {
                feedback.setText(label + ": " + result.changed + "/"
                    + result.attempted + " concluída(s); "
                    + result.failures.size() + " falha(s).");
            }
            refresh(false);
        });
    }

    private void pause(String sessionId) {
        feedback.setText("Pausando sessão…");
        io.execute(() -> {
            try {
                LaboratoryAiLiveSessionRegistry.pause(projectId, sessionId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Sessão pausada.");
                    refresh(false);
                });
            } catch (Exception error) {
                showOperationError("Não foi possível pausar", error);
            }
        });
    }

    private void resume(String sessionId) {
        feedback.setText("Continuando sessão…");
        io.execute(() -> {
            try {
                LaboratoryAiLiveSessionRegistry.resume(projectId, sessionId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Sessão retomada.");
                    refresh(false);
                });
            } catch (Exception error) {
                showOperationError("Não foi possível continuar", error);
            }
        });
    }

    private void confirmComplete(String sessionId) {
        new AlertDialog.Builder(this)
            .setTitle("Finalizar sessão da IA")
            .setMessage("Marcar esta sessão como concluída normalmente? "
                + "Não pode haver ferramenta executando e a sessão não poderá "
                + "ser retomada depois.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("FINALIZAR", (dialog, which) ->
                complete(sessionId))
            .show();
    }

    private void complete(String sessionId) {
        feedback.setText("Finalizando sessão…");
        io.execute(() -> {
            try {
                LaboratoryAiLiveSessionRegistry.complete(projectId, sessionId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Sessão finalizada normalmente.");
                    refresh(false);
                });
            } catch (Exception error) {
                showOperationError("Não foi possível finalizar", error);
            }
        });
    }

    private void confirmCancel(String sessionId) {
        new AlertDialog.Builder(this)
            .setTitle("Cancelar sessão da IA")
            .setMessage("Cancelar definitivamente esta sessão? "
                + "Se houver uma ferramenta em execução, o worker será cancelado. "
                + "O histórico persistido será preservado.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("CANCELAR SESSÃO", (dialog, which) ->
                cancel(sessionId))
            .show();
    }

    private void cancel(String sessionId) {
        feedback.setText("Cancelando sessão…");
        io.execute(() -> {
            try {
                LaboratoryAiLiveSessionRegistry.cancel(projectId, sessionId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Sessão cancelada.");
                    refresh(false);
                });
            } catch (Exception error) {
                showOperationError("Não foi possível cancelar", error);
            }
        });
    }

    private void showOperationError(String prefix, Exception error) {
        runOnUiThread(() -> {
            if (alive()) feedback.setText(prefix + ": " + error.getMessage());
        });
    }

    private LinearLayout.LayoutParams actionParams() {
        LinearLayout.LayoutParams params =
            new LinearLayout.LayoutParams(0, dp(48), 1f);
        params.setMargins(dp(3), 0, dp(3), 0);
        return params;
    }

    private Button button(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(14);
        button.setBackgroundTintList(ColorStateList.valueOf(color));
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

    private boolean alive() {
        return !isFinishing() && !isDestroyed();
    }

    @Override
    protected void onDestroy() {
        main.removeCallbacks(tick);
        io.shutdownNow();
        super.onDestroy();
    }
}
