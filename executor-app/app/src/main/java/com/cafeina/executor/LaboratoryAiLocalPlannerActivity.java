package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
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
 * It may load the selected GGUF and ask for a plan, but it never runs the
 * returned plan. The Goal Lock must remain unused after every probe.
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

    private String projectId;
    private LaboratoryAiTaskContractStore contracts;
    private TextView feedback;
    private TextView modelStatus;
    private LinearLayout entries;
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

        busy = true;
        feedback.setText(
            "Carregando modelo e pedindo um plano JSON…");
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
                        model.modelFile);

                LaboratoryAiTaskContractStore.Contract after =
                    contracts.read(contractId);
                if (after.claimed || after.resultRecorded) {
                    throw new IllegalStateException(
                        "Goal Lock foi alterado durante o planejamento");
                }

                runOnUiThread(() ->
                    showPlannerResult(contractId, result));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Planejamento local falhou: "
                            + String.valueOf(error.getMessage()));
                    refresh();
                    new AlertDialog.Builder(this)
                        .setTitle("Plano não produzido")
                        .setMessage(
                            "Nenhuma ferramenta foi executada e o Goal Lock "
                                + "não deve ser consumido.\n\n"
                                + String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
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

        new AlertDialog.Builder(this)
            .setTitle(title)
            .setView(scroll)
            .setPositiveButton("FECHAR", (dialog, which) -> refresh())
            .setOnCancelListener(dialog -> refresh())
            .show();

        feedback.setText(
            planner.accepted
                ? "Plano aceito pelo contrato determinístico • não executado"
                : "Plano rejeitado após "
                    + planner.attempts + " tentativa(s) • não executado");
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
        worker.shutdownNow();
        super.onDestroy();
    }
}
