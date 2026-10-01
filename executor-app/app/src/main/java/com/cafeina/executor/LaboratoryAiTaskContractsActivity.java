package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputFilter;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private Goal Lock UI.
 *
 * Existing contracts remain immutable. New contracts can only be created from
 * currently granted STABLE tools and are still validated by TaskAdmission.
 */
public final class LaboratoryAiTaskContractsActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private static final int DEFAULT_MAX_INVOCATIONS = 8;
    private static final int DEFAULT_MAX_TOTAL_INPUT_BYTES = 16 * 1024;
    private static final long DEFAULT_MAX_SESSION_MS = 30L * 60L * 1000L;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView feedback;
    private LinearLayout entries;
    private Button createButton;
    private LaboratoryAiTaskContractStore store;
    private String projectId;
    private volatile boolean busy;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("CONTRATOS DA IA • GOAL LOCK", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Crie um Goal Lock com o objetivo exato antes do planejamento. "
                + "Depois de criado, objetivo, modo, ferramentas e orçamento "
                + "ficam imutáveis. O planejador apenas lê o contrato e não o consome.",
            14, MUTED, false), matchWrap());

        createButton = button("CRIAR NOVO GOAL LOCK");
        createButton.setOnClickListener(v -> loadCreationOptions());
        LinearLayout.LayoutParams createParams = matchWrap();
        createParams.setMargins(0, dp(12), 0, dp(8));
        root.addView(createButton, createParams);

        feedback = text("Carregando contratos…", 14, MUTED, false);
        feedback.setPadding(0, dp(4), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        store = new LaboratoryAiTaskContractStore(getFilesDir(), projectId);
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (store != null && !busy) refresh();
    }

    private void loadCreationOptions() {
        if (busy) return;
        busy = true;
        createButton.setEnabled(false);
        feedback.setText("Lendo ferramentas STABLE já concedidas à IA…");

        io.execute(() -> {
            try {
                List<LaboratoryAiToolController.Tool> tools =
                    LaboratoryAiToolController.listAvailable(this, projectId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    createButton.setEnabled(true);
                    if (tools.isEmpty()) {
                        feedback.setText(
                            "Nenhuma ferramenta STABLE está concedida à IA.");
                        new AlertDialog.Builder(this)
                            .setTitle("Goal Lock precisa de ferramentas")
                            .setMessage(
                                "Ainda não há ferramenta STABLE concedida à IA "
                                    + "neste projeto. Conceda ao menos uma em "
                                    + "Permissões da IA e volte para criar o contrato.")
                            .setNegativeButton("FECHAR", null)
                            .setPositiveButton(
                                "ABRIR PERMISSÕES",
                                (dialog, which) -> startActivity(new Intent(
                                    this, LaboratoryAiPermissionsActivity.class)))
                            .show();
                        return;
                    }
                    showCreateDialog(tools);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    createButton.setEnabled(true);
                    feedback.setText(
                        "Falha ao ler ferramentas: "
                            + String.valueOf(error.getMessage()));
                });
            }
        });
    }

    private void showCreateDialog(List<LaboratoryAiToolController.Tool> tools) {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(14), dp(10), dp(14), dp(10));

        form.addView(text(
            "Modo do Goal Lock",
            13, FG, true), matchWrap());

        RadioGroup modes = new RadioGroup(this);
        modes.setOrientation(RadioGroup.HORIZONTAL);
        RadioButton creation = new RadioButton(this);
        creation.setId(View.generateViewId());
        creation.setText("CRIAÇÃO");
        creation.setTextColor(FG);
        creation.setChecked(true);
        RadioButton learning = new RadioButton(this);
        learning.setId(View.generateViewId());
        learning.setText("APRENDIZADO");
        learning.setTextColor(FG);
        modes.addView(creation);
        modes.addView(learning);
        form.addView(modes, matchWrap());

        TextView goalLabel = text(
            "Objetivo exato",
            13, FG, true);
        goalLabel.setPadding(0, dp(10), 0, dp(4));
        form.addView(goalLabel, matchWrap());

        EditText goal = new EditText(this);
        goal.setTextColor(FG);
        goal.setHintTextColor(MUTED);
        goal.setHint(
            "Ex.: analisar a ferramenta e produzir um plano de teste controlado");
        goal.setMinLines(3);
        goal.setMaxLines(8);
        goal.setSingleLine(false);
        goal.setFilters(new InputFilter[] {
            new InputFilter.LengthFilter(
                LaboratoryAiTaskContractStore.MAX_GOAL_CHARS)
        });
        form.addView(goal, matchWrap());

        TextView toolsLabel = text(
            "Ferramentas já concedidas que este contrato poderá usar",
            13, FG, true);
        toolsLabel.setPadding(0, dp(10), 0, dp(4));
        form.addView(toolsLabel, matchWrap());

        List<CheckBox> checks = new ArrayList<>();
        for (LaboratoryAiToolController.Tool tool : tools) {
            CheckBox check = new CheckBox(this);
            check.setText(
                tool.toolId + " • " + tool.version
                    + (tool.capabilities.isEmpty()
                        ? ""
                        : "\n" + tool.capabilities));
            check.setTextColor(FG);
            check.setTag(tool.toolId);
            check.setChecked(true);
            checks.add(check);
            form.addView(check, matchWrap());
        }

        TextView budget = text(
            "Orçamento da execução da Testadora: "
                + DEFAULT_MAX_INVOCATIONS + " chamadas • "
                + (DEFAULT_MAX_TOTAL_INPUT_BYTES / 1024)
                + " KiB de entrada • 30 min. "
                + "Esse limite é da sessão de ferramentas; não é o tempo "
                + "de raciocínio do modelo.",
            12, MUTED, false);
        budget.setPadding(0, dp(10), 0, 0);
        form.addView(budget, matchWrap());

        ScrollView scroll = new ScrollView(this);
        scroll.addView(form);

        AlertDialog dialog = new AlertDialog.Builder(this)
            .setTitle("Criar Goal Lock")
            .setView(scroll)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CRIAR", null)
            .create();

        dialog.setOnShowListener(ignored ->
            dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String exactGoal = goal.getText().toString();
                    if (exactGoal.trim().isEmpty()) {
                        goal.setError("Digite o objetivo exato");
                        return;
                    }

                    List<String> selectedTools = new ArrayList<>();
                    for (CheckBox check : checks) {
                        if (check.isChecked()) {
                            selectedTools.add(String.valueOf(check.getTag()));
                        }
                    }
                    if (selectedTools.isEmpty()) {
                        feedback.setText(
                            "Selecione ao menos uma ferramenta para o Goal Lock.");
                        return;
                    }

                    LaboratoryAiTaskContractStore.Mode mode =
                        modes.getCheckedRadioButtonId() == learning.getId()
                            ? LaboratoryAiTaskContractStore.Mode.LEARNING
                            : LaboratoryAiTaskContractStore.Mode.CREATION;

                    dialog.dismiss();
                    createGoalLock(mode, exactGoal, selectedTools);
                }));
        dialog.show();
    }

    private void createGoalLock(
            LaboratoryAiTaskContractStore.Mode mode,
            String exactGoal,
            List<String> toolIds) {
        if (busy) return;
        busy = true;
        createButton.setEnabled(false);
        feedback.setText("Criando Goal Lock imutável…");

        io.execute(() -> {
            try {
                LaboratoryAiSessionController.Policy policy =
                    new LaboratoryAiSessionController.Policy(
                        toolIds,
                        DEFAULT_MAX_INVOCATIONS,
                        DEFAULT_MAX_TOTAL_INPUT_BYTES,
                        DEFAULT_MAX_SESSION_MS);

                LaboratoryAiTaskContractStore.Contract contract =
                    LaboratoryAiTaskAdmission.createContract(
                        this,
                        projectId,
                        mode,
                        exactGoal,
                        policy);

                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    createButton.setEnabled(true);
                    feedback.setText(
                        "Goal Lock criado • pronto para o planejador local");
                    refresh();

                    new AlertDialog.Builder(this)
                        .setTitle("Goal Lock criado")
                        .setMessage(
                            "Modo: " + contract.mode.name()
                                + "\nContrato: " + contract.contractId
                                + "\nObjetivo SHA-256: " + contract.goalSha256
                                + "\nFerramentas: " + contract.allowedToolIds
                                + "\n\nO contrato ainda NÃO foi consumido.")
                        .setNegativeButton("FICAR AQUI", null)
                        .setPositiveButton(
                            "TESTAR PLANEJADOR",
                            (dialog, which) -> startActivity(new Intent(
                                this, LaboratoryAiLocalPlannerActivity.class)))
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    createButton.setEnabled(true);
                    feedback.setText(
                        "Goal Lock não foi criado: "
                            + String.valueOf(error.getMessage()));
                    new AlertDialog.Builder(this)
                        .setTitle("Falha ao criar Goal Lock")
                        .setMessage(String.valueOf(error.getMessage()))
                        .setPositiveButton("OK", null)
                        .show();
                });
            }
        });
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryAiTaskContractStore.Contract> contracts = store.list();
                runOnUiThread(() -> render(contracts));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao ler contratos: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryAiTaskContractStore.Contract> contracts) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(contracts.size() + " contrato(s) neste projeto");

        if (contracts.isEmpty()) {
            entries.addView(text(
                "Nenhum Goal Lock foi criado ainda. "
                    + "Use “CRIAR NOVO GOAL LOCK” acima para preparar "
                    + "o primeiro teste do planejador.",
                14, MUTED, false), matchWrap());
            return;
        }

        for (LaboratoryAiTaskContractStore.Contract contract : contracts) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            String status = contract.resultRecorded
                ? "RESULTADO REGISTRADO"
                : contract.claimed
                    ? "REIVINDICADO • SEM RESULTADO"
                    : "PRONTO • NÃO CONSUMIDO";

            TextView details = text(
                contract.mode.name() + " • " + status
                    + "\nContrato: " + contract.contractId
                    + "\nCriado: " + time(contract.createdAtEpochMs)
                    + "\nObjetivo SHA-256: " + contract.goalSha256
                    + "\nFerramentas: " + contract.allowedToolIds
                    + "\nChamadas: " + contract.maxInvocations
                    + " • Entrada: " + contract.maxTotalInputBytes + " bytes"
                    + "\nTempo máximo: " + contract.maxSessionMs + " ms",
                13, FG, true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            Button goal = button("VER OBJETIVO EXATO");
            goal.setOnClickListener(v -> showGoal(contract));
            LinearLayout.LayoutParams goalParams = matchWrap();
            goalParams.setMargins(0, dp(8), 0, 0);
            card.addView(goal, goalParams);

            if (!contract.claimed && !contract.resultRecorded) {
                Button planner = button("TESTAR NO PLANEJADOR LOCAL");
                planner.setOnClickListener(v -> startActivity(new Intent(
                    this, LaboratoryAiLocalPlannerActivity.class)));
                LinearLayout.LayoutParams plannerParams = matchWrap();
                plannerParams.setMargins(0, dp(8), 0, 0);
                card.addView(planner, plannerParams);
            }

            if (contract.resultRecorded) {
                Button result = button("VER RESULTADO DA ADMISSÃO");
                result.setOnClickListener(v -> showResult(contract));
                LinearLayout.LayoutParams resultParams = matchWrap();
                resultParams.setMargins(0, dp(8), 0, 0);
                card.addView(result, resultParams);
            }

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }
    }

    private void showGoal(LaboratoryAiTaskContractStore.Contract contract) {
        TextView view = text(contract.goalText, 14, FG, false);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextIsSelectable(true);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);

        new AlertDialog.Builder(this)
            .setTitle("Objetivo travado • " + contract.mode.name())
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private void showResult(LaboratoryAiTaskContractStore.Contract contract) {
        io.execute(() -> {
            try {
                LaboratoryAiTaskContractStore.Result result =
                    store.readResult(contract.contractId);
                String details = "Status: " + result.status
                    + "\nSessão: "
                    + (result.sessionId.isEmpty() ? "nenhuma" : result.sessionId)
                    + "\nMotivo: "
                    + (result.reason.isEmpty() ? "—" : result.reason)
                    + "\nRegistrado: " + time(result.recordedAtEpochMs);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    TextView view = text(details, 13, FG, false);
                    view.setTypeface(Typeface.MONOSPACE);
                    view.setTextIsSelectable(true);
                    view.setPadding(dp(14), dp(12), dp(14), dp(12));
                    new AlertDialog.Builder(this)
                        .setTitle("Admissão do contrato")
                        .setView(view)
                        .setPositiveButton("FECHAR", null)
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Resultado indisponível: " + error.getMessage());
                });
            }
        });
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(14);
        button.setBackgroundTintList(ColorStateList.valueOf(ACCENT));
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

    private static String time(long epochMs) {
        if (epochMs <= 0) return "Data indisponível";
        return DateFormat.getDateTimeInstance(
            DateFormat.SHORT, DateFormat.SHORT,
            new Locale("pt", "BR")).format(new Date(epochMs));
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
