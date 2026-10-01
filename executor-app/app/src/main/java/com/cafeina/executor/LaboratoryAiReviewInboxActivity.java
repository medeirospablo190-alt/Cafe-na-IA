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
 * Read-only view of proposals explicitly routed by the user.
 */
public final class LaboratoryAiReviewInboxActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiReviewInbox inbox;

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

        TextView title = text("CAIXA DE REVISÃO • EQUIPE DE IAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Somente propostas que você marcou como ENVIAR PARA REVISÃO "
                + "aparecem aqui. Estar nesta caixa autoriza análise, não aplicação.",
            13, MUTED, false), matchWrap());

        feedback = text("Carregando fila de revisão…", 14, MUTED, false);
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
        inbox = new LaboratoryAiReviewInbox(getFilesDir(), projectId);
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (inbox != null) refresh();
    }

    private void refresh() {
        io.execute(() -> {
            List<LaboratoryAiReviewInbox.Item> items;
            String problem = null;
            try {
                items = inbox.listAllRouted();
            } catch (Exception error) {
                items = Collections.emptyList();
                problem = error.getMessage();
            }

            final List<LaboratoryAiReviewInbox.Item> result = items;
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha na caixa de revisão: " + failure);
                    return;
                }

                feedback.setText(result.size()
                    + " proposta(s) autorizada(s) para análise");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Nenhuma proposta foi enviada para revisão.",
                        14, MUTED, false), matchWrap());
                    return;
                }

                String lastRole = null;
                for (LaboratoryAiReviewInbox.Item item : result) {
                    if (!item.targetRole.equals(lastRole)) {
                        TextView section = text(
                            "DESTINO • " + item.targetRole, 16, FG, true);
                        section.setPadding(0, dp(14), 0, dp(2));
                        entries.addView(section, matchWrap());
                        lastRole = item.targetRole;
                    }

                    Button entry = button(
                        item.agentId + " • " + item.sourceRecommendationCode
                            + "\n" + item.suggestedActionCode
                            + "\nRoteada: " + time(item.routedAtEpochMs));
                    entry.setAllCaps(false);
                    entry.setGravity(android.view.Gravity.START
                        | android.view.Gravity.CENTER_VERTICAL);
                    entry.setOnClickListener(v -> show(item));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    entries.addView(entry, params);
                }
            });
        });
    }

    private void show(LaboratoryAiReviewInbox.Item item) {
        String details =
            "Proposta: " + item.proposalId
            + "\nIA afetada: " + item.agentId
            + "\nPapel atual: " + item.agentRole
            + "\nDestino autorizado: " + item.targetRole
            + "\nSinal: " + item.sourceRecommendationCode
            + "\nAção sugerida: " + item.suggestedActionCode
            + "\nTendência: " + item.sourceTrend
            + "\nSessões observadas: " + item.sourceSessionCount
            + "\nSessões com falha: " + item.sourceFailureSessions
            + "\nFalhas de ferramenta: " + item.sourceFailedInvocations
            + "\nEventos de decisão: " + item.decisionEventCount
            + "\nRoteada: " + time(item.routedAtEpochMs)
            + "\n\nEsta caixa não aplica a melhoria e não executa ferramentas.";

        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);

        new AlertDialog.Builder(this)
            .setTitle("Item para revisão • somente leitura")
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
