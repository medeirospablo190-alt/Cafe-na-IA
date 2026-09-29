package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * User-facing review of candidate EVIDENCE, never a tool console.
 * The only decisions here authorize more laboratory evaluation or reject the
 * candidate for now. Neither option activates or promotes a tool to STABLE.
 */
public final class LaboratoryReviewActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(173, 181, 194);
    private static final int PANEL = Color.rgb(35, 43, 55);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LaboratoryToolRegistry registry;
    private LaboratoryReviewDecisionStore decisions;
    private TextView status;
    private LinearLayout entries;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        String projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR AO SISTEMA");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = label("REVISÃO DAS FERRAMENTAS", 21, FG, true);
        title.setPadding(0, dp(14), 0, dp(8));
        root.addView(title, matchWrap());
        root.addView(label(
            "Esta área registra suas decisões. AUTORIZAR significa permitir "
                + "que a ferramenta seja estudada e testada novamente no laboratório; "
                + "não instala, executa, publica nem ativa uma versão estável.",
            14, MUTED, false), matchWrap());
        status = label("Consultando ferramentas candidatas…", 14, MUTED, false);
        status.setPadding(0, dp(12), 0, dp(8));
        root.addView(status, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        try {
            registry = new LaboratoryToolRegistry(getFilesDir(), projectId);
            decisions = new LaboratoryReviewDecisionStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            status.setText("Revisão indisponível: " + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryToolRegistry.Tool> all = registry.list();
                java.util.ArrayList<ReviewItem> items = new java.util.ArrayList<>();
                for (LaboratoryToolRegistry.Tool tool : all) {
                    if (tool.state == LaboratoryToolRegistry.State.CANDIDATE) {
                        items.add(new ReviewItem(tool, decisions.read(tool.id, tool.version)));
                    }
                }
                runOnUiThread(() -> {
                    if (!alive()) return;
                    entries.removeAllViews();
                    status.setText(items.size() + " candidata(s) neste projeto");
                    if (items.isEmpty()) {
                        entries.addView(label(
                            "Nenhuma ferramenta aguarda revisão. O laboratório "
                                + "continua sem ativar ferramentas automaticamente.",
                            14, MUTED, false), matchWrap());
                    }
                    for (ReviewItem item : items) addCandidate(item);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) status.setText(
                        "Falha ao verificar evidências: " + error.getMessage());
                });
            }
        });
    }

    private void addCandidate(ReviewItem item) {
        LaboratoryToolRegistry.Tool tool = item.tool;
        String heading = tool.id + " @ " + tool.version + "\n"
            + (item.decision == null ? "AGUARDANDO SUA REVISÃO"
                : item.decision.decision
                    == LaboratoryReviewDecisionStore.Decision.CONTINUE_TESTING
                    ? "AUTORIZADA PARA MAIS TESTES • NÃO ESTÁVEL"
                    : "REJEITADA POR ENQUANTO");
        Button open = button(heading);
        open.setAllCaps(false);
        open.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        open.setBackgroundTintList(ColorStateList.valueOf(PANEL));
        open.setOnClickListener(v -> showCandidate(item));
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, 0);
        entries.addView(open, params);
    }

    private void showCandidate(ReviewItem item) {
        LaboratoryToolRegistry.Tool tool = item.tool;
        String description = "Ferramenta: " + tool.id
            + "\nVersão: " + tool.version
            + "\nEstado: CANDIDATA • NÃO ESTÁVEL"
            + "\nCapacidade fixa: " + tool.capability
            + "\nLimite: " + tool.timeoutMs + " ms"
            + "\nFonte SHA-256: " + tool.sourceSha256
            + "\nManifesto SHA-256: " + tool.manifestSha256
            + "\nSnapshot: " + tool.snapshotId
            + "\nTeste aprovado para revisão: " + tool.evidenceRunId
            + "\n\nA decisão não executa esta ferramenta nem altera "
            + "seus scripts, o Mundo ou o núcleo do aplicativo.";
        if (item.decision != null) {
            description += "\n\nDecisão já registrada: " + item.decision.decision.name()
                + "\nNão é permitido sobrescrever o histórico.";
        }
        TextView text = label(description, 13, FG, false);
        text.setTypeface(Typeface.MONOSPACE);
        text.setTextIsSelectable(true);
        text.setPadding(dp(14), dp(10), dp(14), dp(10));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(text);
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
            .setTitle("Revisar versão e evidências")
            .setView(scroll)
            .setNegativeButton("FECHAR", null);
        if (item.decision == null) {
            builder.setPositiveButton("AUTORIZAR MAIS TESTES",
                (dialog, which) -> confirm(item,
                    LaboratoryReviewDecisionStore.Decision.CONTINUE_TESTING));
            builder.setNeutralButton("REJEITAR POR ENQUANTO",
                (dialog, which) -> confirm(item,
                    LaboratoryReviewDecisionStore.Decision.REJECT_FOR_NOW));
        }
        builder.show();
    }

    private void confirm(ReviewItem item, LaboratoryReviewDecisionStore.Decision decision) {
        String phrase = decision == LaboratoryReviewDecisionStore.Decision.CONTINUE_TESTING
            ? "AUTORIZAR" : "REJEITAR";
        EditText confirmation = new EditText(this);
        confirmation.setSingleLine(true);
        confirmation.setTextColor(FG);
        confirmation.setHintTextColor(MUTED);
        confirmation.setHint("Digite " + phrase);
        confirmation.setInputType(InputType.TYPE_CLASS_TEXT
            | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setPadding(dp(18), dp(8), dp(18), 0);
        wrapper.addView(confirmation, matchWrap());
        AlertDialog prompt = new AlertDialog.Builder(this)
            .setTitle("Confirmar decisão para " + item.tool.id + " @ " + item.tool.version)
            .setMessage("Digite " + phrase + " para registrar sua escolha. "
                + "Não há ativação da ferramenta ou alteração de arquivos do projeto.")
            .setView(wrapper)
            .setNegativeButton("VOLTAR", null)
            .setPositiveButton("REGISTRAR DECISÃO", null)
            .create();
        prompt.setOnShowListener(unused ->
            prompt.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                if (!phrase.equals(confirmation.getText().toString().trim())) {
                    confirmation.setError("Digite exatamente " + phrase);
                    return;
                }
                prompt.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
                status.setText("Registrando decisão, sem ativar a ferramenta…");
                io.execute(() -> {
                    try {
                        decisions.recordDecision(item.tool.id, item.tool.version, decision);
                        runOnUiThread(() -> {
                            if (!alive()) return;
                            prompt.dismiss();
                            refresh();
                        });
                    } catch (Exception error) {
                        runOnUiThread(() -> {
                            if (!alive()) return;
                            status.setText("Decisão não registrada: " + error.getMessage());
                            prompt.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);
                        });
                    }
                });
            }));
        prompt.show();
    }

    private static final class ReviewItem {
        final LaboratoryToolRegistry.Tool tool;
        final LaboratoryReviewDecisionStore.Entry decision;
        ReviewItem(LaboratoryToolRegistry.Tool tool,
                LaboratoryReviewDecisionStore.Entry decision) {
            this.tool = tool;
            this.decision = decision;
        }
    }

    private Button button(String value) {
        Button view = new Button(this);
        view.setText(value);
        view.setTextColor(FG);
        view.setTextSize(14);
        view.setAllCaps(false);
        return view;
    }

    private TextView label(String value, int sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(sp);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private boolean alive() { return !isFinishing() && !isDestroyed(); }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
