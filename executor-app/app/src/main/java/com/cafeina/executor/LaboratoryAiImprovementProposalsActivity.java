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
 * Read-only queue of diagnostic improvement proposals.
 */
public final class LaboratoryAiImprovementProposalsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiImprovementProposalStore store;
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

        TextView title = text("PROPOSTAS DE MELHORIA • IAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Sugestões geradas a partir dos diagnósticos da equipe. "
                + "Nenhuma proposta altera código, orçamento, ferramenta ou IA "
                + "automaticamente.",
            13, MUTED, false), matchWrap());

        feedback = text("Atualizando propostas…", 14, MUTED, false);
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
        store = new LaboratoryAiImprovementProposalStore(
            getFilesDir(), projectId);
        refresh(true);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null) refresh(true);
    }

    private void refresh(boolean regenerate) {
        io.execute(() -> {
            List<LaboratoryAiImprovementProposalStore.Proposal> proposals;
            String problem = null;
            try {
                if (regenerate) {
                    LaboratoryAiImprovementPlanner.refreshNow(
                        getApplicationContext(), projectId);
                }
                proposals = store.list();
            } catch (Exception error) {
                proposals = Collections.emptyList();
                problem = error.getMessage();
            }

            final List<LaboratoryAiImprovementProposalStore.Proposal> result =
                proposals;
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha nas propostas: " + failure);
                    return;
                }

                feedback.setText(result.size()
                    + " proposta(s) • somente leitura • nenhuma aplicação automática");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Nenhuma melhoria foi proposta pelos diagnósticos atuais.",
                        14, MUTED, false), matchWrap());
                    return;
                }

                for (LaboratoryAiImprovementProposalStore.Proposal proposal
                        : result) {
                    Button item = button(
                        proposal.agentId + " • " + proposal.agentRole
                            + "\n" + proposal.sourceRecommendationCode
                            + " → " + proposal.suggestedActionCode
                            + "\nRevisão sugerida: " + proposal.targetRole);
                    item.setAllCaps(false);
                    item.setGravity(android.view.Gravity.START
                        | android.view.Gravity.CENTER_VERTICAL);
                    item.setOnClickListener(v -> show(proposal));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    entries.addView(item, params);
                }
            });
        });
    }

    private void show(
            LaboratoryAiImprovementProposalStore.Proposal proposal) {
        String details =
            "Proposta: " + proposal.proposalId
            + "\nIA afetada: " + proposal.agentId
            + "\nPapel atual: " + proposal.agentRole
            + "\nSinal do diagnóstico: "
            + proposal.sourceRecommendationCode
            + "\nAção sugerida: " + proposal.suggestedActionCode
            + "\nPapel sugerido para revisar: " + proposal.targetRole
            + "\nTendência de origem: " + proposal.sourceTrend
            + "\nSessões observadas: " + proposal.sourceSessionCount
            + "\nSessões com falha: " + proposal.sourceFailureSessions
            + "\nFalhas de ferramenta: " + proposal.sourceFailedInvocations
            + "\nCriada: " + time(proposal.createdAtEpochMs)
            + "\nChave de deduplicação SHA-256: "
            + proposal.proposalKeySha256
            + "\n\nEsta proposta não executa nenhuma alteração.";

        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);

        new AlertDialog.Builder(this)
            .setTitle("Proposta de melhoria • somente leitura")
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
