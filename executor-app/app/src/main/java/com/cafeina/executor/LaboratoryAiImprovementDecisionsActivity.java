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

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Host-only workflow decisions for diagnostic improvement proposals.
 *
 * Routing means "approved for later review", not "apply this improvement".
 */
public final class LaboratoryAiImprovementDecisionsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);
    private static final int ACCENT = Color.rgb(82, 118, 255);
    private static final int DISMISS = Color.rgb(126, 56, 61);
    private static final int REOPEN = Color.rgb(148, 111, 47);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private String projectId;
    private LaboratoryAiImprovementProposalStore proposals;
    private LaboratoryAiImprovementDecisionStore decisions;

    private static final class Row {
        final LaboratoryAiImprovementProposalStore.Proposal proposal;
        final LaboratoryAiImprovementDecisionStore.State state;

        Row(LaboratoryAiImprovementProposalStore.Proposal proposal,
                LaboratoryAiImprovementDecisionStore.State state) {
            this.proposal = proposal;
            this.state = state;
        }
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(16), dp(16), dp(16));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR", ACCENT);
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("DECISÕES • MELHORIAS DAS IAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Aqui você decide o destino de uma proposta. "
                + "ENVIAR PARA REVISÃO não executa a mudança; apenas registra "
                + "que ela poderá ser analisada pelo papel indicado.",
            13, MUTED, false), matchWrap());

        feedback = text("Carregando decisões…", 14, MUTED, false);
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
        proposals = new LaboratoryAiImprovementProposalStore(
            getFilesDir(), projectId);
        decisions = new LaboratoryAiImprovementDecisionStore(
            getFilesDir(), projectId);
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (proposals != null && decisions != null) refresh();
    }

    private void refresh() {
        io.execute(() -> {
            List<Row> rows = new ArrayList<>();
            String problem = null;
            try {
                LaboratoryAiImprovementPlanner.refreshNow(
                    getApplicationContext(), projectId);
                for (LaboratoryAiImprovementProposalStore.Proposal proposal
                        : proposals.list()) {
                    rows.add(new Row(
                        proposal,
                        decisions.state(proposal.proposalId)));
                }
            } catch (Exception error) {
                rows.clear();
                problem = error.getMessage();
            }

            final List<Row> result =
                Collections.unmodifiableList(new ArrayList<>(rows));
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha ao ler decisões: " + failure);
                    return;
                }
                feedback.setText(result.size()
                    + " proposta(s) • decisões append-only");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Nenhuma proposta aguarda decisão.",
                        14, MUTED, false), matchWrap());
                    return;
                }
                for (Row row : result) renderRow(row);
            });
        });
    }

    private void renderRow(Row row) {
        LaboratoryAiImprovementProposalStore.Proposal proposal = row.proposal;
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

        TextView details = text(
            proposal.agentId + " • " + proposal.agentRole
                + "\n" + proposal.sourceRecommendationCode
                + " → " + proposal.suggestedActionCode
                + "\nRevisor sugerido: " + proposal.targetRole
                + "\nEstado: " + row.state.status
                + "\nEventos de decisão: " + row.state.eventCount,
            13, FG, true);
        details.setTextIsSelectable(true);
        card.addView(details, matchWrap());

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);

        if (LaboratoryAiImprovementDecisionStore.STATE_PENDING
                .equals(row.state.status)) {
            Button route = button("ENVIAR PARA REVISÃO", ACCENT);
            route.setOnClickListener(v -> confirmRoute(proposal));
            actions.addView(route, actionParams());

            Button dismiss = button("DISPENSAR", DISMISS);
            dismiss.setOnClickListener(v -> confirmDismiss(proposal));
            actions.addView(dismiss, actionParams());
        } else if (LaboratoryAiImprovementDecisionStore.STATE_ROUTED
                .equals(row.state.status)) {
            Button reopen = button("REABRIR", REOPEN);
            reopen.setOnClickListener(v -> confirmReopen(proposal));
            actions.addView(reopen, actionParams());

            Button dismiss = button("DISPENSAR", DISMISS);
            dismiss.setOnClickListener(v -> confirmDismiss(proposal));
            actions.addView(dismiss, actionParams());
        } else if (LaboratoryAiImprovementDecisionStore.STATE_DISMISSED
                .equals(row.state.status)) {
            Button reopen = button("REABRIR", REOPEN);
            reopen.setOnClickListener(v -> confirmReopen(proposal));
            actions.addView(reopen, actionParams());
        }

        LinearLayout.LayoutParams actionRow = matchWrap();
        actionRow.setMargins(0, dp(8), 0, 0);
        card.addView(actions, actionRow);

        LinearLayout.LayoutParams cardParams = matchWrap();
        cardParams.setMargins(0, dp(8), 0, 0);
        entries.addView(card, cardParams);
    }

    private void confirmRoute(
            LaboratoryAiImprovementProposalStore.Proposal proposal) {
        new AlertDialog.Builder(this)
            .setTitle("Enviar para revisão")
            .setMessage("Marcar esta proposta para revisão pelo papel "
                + proposal.targetRole + "?\n\n"
                + "Isto NÃO aplica a melhoria e não executa ferramenta.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("ENVIAR", (dialog, which) ->
                decide(proposal.proposalId,
                    LaboratoryAiImprovementDecisionStore.ACTION_ROUTE))
            .show();
    }

    private void confirmDismiss(
            LaboratoryAiImprovementProposalStore.Proposal proposal) {
        new AlertDialog.Builder(this)
            .setTitle("Dispensar proposta")
            .setMessage("Marcar esta proposta como dispensada? "
                + "O histórico será preservado e ela poderá ser reaberta.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("DISPENSAR", (dialog, which) ->
                decide(proposal.proposalId,
                    LaboratoryAiImprovementDecisionStore.ACTION_DISMISS))
            .show();
    }

    private void confirmReopen(
            LaboratoryAiImprovementProposalStore.Proposal proposal) {
        new AlertDialog.Builder(this)
            .setTitle("Reabrir proposta")
            .setMessage("Voltar esta proposta para PENDING? "
                + "Nenhuma mudança será executada.")
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("REABRIR", (dialog, which) ->
                decide(proposal.proposalId,
                    LaboratoryAiImprovementDecisionStore.ACTION_REOPEN))
            .show();
    }

    private void decide(String proposalId, String action) {
        feedback.setText("Registrando decisão…");
        io.execute(() -> {
            try {
                decisions.append(proposalId, action);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Decisão registrada.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Decisão não registrada: " + error.getMessage());
                });
            }
        });
    }

    private LinearLayout.LayoutParams actionParams() {
        LinearLayout.LayoutParams params =
            new LinearLayout.LayoutParams(0, dp(48), 1f);
        params.setMargins(dp(3), 0, dp(3), 0);
        return params;
    }

    private Button button(String label, int color) {
        Button result = new Button(this);
        result.setText(label);
        result.setTextSize(13);
        result.setTextColor(FG);
        result.setBackgroundTintList(ColorStateList.valueOf(color));
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

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
