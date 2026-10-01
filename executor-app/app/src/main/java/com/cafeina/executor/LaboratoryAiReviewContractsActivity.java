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
 * Read-only visibility for one-use review contracts.
 */
public final class LaboratoryAiReviewContractsActivity extends Activity {
    private static final int BG = Color.rgb(16, 18, 23);
    private static final int PANEL = Color.rgb(31, 35, 43);
    private static final int FG = Color.rgb(239, 242, 247);
    private static final int MUTED = Color.rgb(166, 174, 188);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryAiReviewContractStore store;

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

        TextView title = text("CONTRATOS DE REVISÃO • IAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Cada contrato autoriza somente a análise de uma proposta e fica "
                + "preso ao evento exato em que ela foi enviada para revisão. "
                + "Não autoriza aplicar mudanças.",
            13, MUTED, false), matchWrap());

        feedback = text("Carregando contratos…", 14, MUTED, false);
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
        store = new LaboratoryAiReviewContractStore(getFilesDir(), projectId);
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null) refresh();
    }

    private void refresh() {
        io.execute(() -> {
            List<LaboratoryAiReviewContractStore.Contract> contracts;
            String problem = null;
            try {
                contracts = store.list();
            } catch (Exception error) {
                contracts = Collections.emptyList();
                problem = error.getMessage();
            }

            final List<LaboratoryAiReviewContractStore.Contract> result =
                contracts;
            final String failure = problem;
            runOnUiThread(() -> {
                if (!alive()) return;
                entries.removeAllViews();
                if (failure != null) {
                    feedback.setText("Falha nos contratos: " + failure);
                    return;
                }

                feedback.setText(result.size()
                    + " contrato(s) de revisão • somente leitura");
                if (result.isEmpty()) {
                    entries.addView(text(
                        "Nenhum contrato de revisão foi criado.",
                        14, MUTED, false), matchWrap());
                    return;
                }

                for (LaboratoryAiReviewContractStore.Contract contract
                        : result) {
                    Button item = button(
                        contract.targetRole + " • "
                            + (contract.claimed
                                ? "REIVINDICADO" : "NÃO REIVINDICADO")
                            + "\n" + contract.sourceRecommendationCode
                            + " → " + contract.suggestedActionCode
                            + "\n" + time(contract.createdAtEpochMs));
                    item.setAllCaps(false);
                    item.setGravity(android.view.Gravity.START
                        | android.view.Gravity.CENTER_VERTICAL);
                    item.setOnClickListener(v -> show(contract));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    entries.addView(item, params);
                }
            });
        });
    }

    private void show(LaboratoryAiReviewContractStore.Contract contract) {
        String details =
            "Contrato: " + contract.reviewContractId
            + "\nProposta: " + contract.proposalId
            + "\nProposta SHA-256: " + contract.proposalKeySha256
            + "\nPapel autorizado: " + contract.targetRole
            + "\nEvento de roteamento: " + contract.routingEventId
            + "\nSequência do roteamento: " + contract.routingSequence
            + "\nRoteamento SHA-256: " + contract.routingRecordSha256
            + "\nSinal: " + contract.sourceRecommendationCode
            + "\nAção sugerida: " + contract.suggestedActionCode
            + "\nCriado: " + time(contract.createdAtEpochMs)
            + "\nClaim: " + (contract.claimed ? "SIM" : "NÃO")
            + "\nContrato SHA-256: " + contract.contractSha256
            + "\n\nO contrato autoriza análise, não aplicação.";

        TextView body = text(details, 13, FG, false);
        body.setTypeface(Typeface.MONOSPACE);
        body.setTextIsSelectable(true);
        body.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(body);

        new AlertDialog.Builder(this)
            .setTitle("Contrato de revisão • somente leitura")
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
