package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
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

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Host-owned UI for creating an immutable Goal Lock from the exact user goal.
 *
 * Only STABLE tools already granted to the AI can be selected. Contract
 * creation runs through LaboratoryAiTaskAdmission, so this screen cannot
 * bypass the deterministic permission boundary.
 */
public final class LaboratoryAiGoalLockCreateActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private static final int DEFAULT_MAX_INVOCATIONS = 8;
    private static final int DEFAULT_MAX_TOTAL_INPUT_BYTES = 32 * 1024;
    private static final long DEFAULT_MAX_SESSION_MS = 5L * 60L * 1000L;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final List<ToolChoice> toolChoices = new ArrayList<>();

    private String projectId;
    private EditText goalInput;
    private RadioButton creationMode;
    private RadioButton learningMode;
    private LinearLayout toolsContainer;
    private TextView feedback;
    private Button createButton;
    private Button permissionsButton;
    private volatile boolean busy;

    private static final class ToolChoice {
        final LaboratoryAiToolController.Tool tool;
        final CheckBox checkBox;

        ToolChoice(LaboratoryAiToolController.Tool tool, CheckBox checkBox) {
            this.tool = tool;
            this.checkBox = checkBox;
        }
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(20));
        root.setBackgroundColor(BG);
        scroll.addView(root);
        setContentView(scroll);

        Button back = button("← VOLTAR", PANEL);
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("CRIAR GOAL LOCK", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "O objetivo abaixo será gravado exatamente como você escrever. "
                + "Depois de criado, modo, objetivo, ferramentas e orçamento "
                + "não podem ser alterados nesse contrato.",
            14, MUTED, false), matchWrap());

        TextView goalLabel = text("OBJETIVO EXATO", 13, FG, true);
        goalLabel.setPadding(0, dp(16), 0, dp(6));
        root.addView(goalLabel, matchWrap());

        goalInput = new EditText(this);
        goalInput.setTextColor(FG);
        goalInput.setHintTextColor(MUTED);
        goalInput.setHint(
            "Ex.: verificar a ferramenta selecionada e produzir um plano de teste seguro.");
        goalInput.setTextSize(15);
        goalInput.setMinLines(4);
        goalInput.setGravity(Gravity.TOP | Gravity.START);
        goalInput.setInputType(
            InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        goalInput.setPadding(dp(12), dp(10), dp(12), dp(10));
        root.addView(goalInput, matchWrap());

        TextView modeLabel = text("MODO", 13, FG, true);
        modeLabel.setPadding(0, dp(16), 0, dp(4));
        root.addView(modeLabel, matchWrap());

        RadioGroup modeGroup = new RadioGroup(this);
        modeGroup.setOrientation(LinearLayout.VERTICAL);
        creationMode = radio("CRIAÇÃO • cumprir um objetivo definido");
        learningMode = radio("APRENDIZADO • estudar/testar sem mudar o objetivo");
        creationMode.setId(View.generateViewId());
        learningMode.setId(View.generateViewId());
        modeGroup.addView(creationMode);
        modeGroup.addView(learningMode);
        modeGroup.check(creationMode.getId());
        root.addView(modeGroup, matchWrap());

        TextView toolsLabel = text("FERRAMENTAS PERMITIDAS", 13, FG, true);
        toolsLabel.setPadding(0, dp(16), 0, dp(4));
        root.addView(toolsLabel, matchWrap());

        root.addView(text(
            "Só aparecem ferramentas STABLE que você já liberou para a IA. "
                + "Para este primeiro teste, todas vêm marcadas; você pode desmarcar.",
            13, MUTED, false), matchWrap());

        toolsContainer = new LinearLayout(this);
        toolsContainer.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams toolsParams = matchWrap();
        toolsParams.setMargins(0, dp(8), 0, 0);
        root.addView(toolsContainer, toolsParams);

        permissionsButton = button("ABRIR PERMISSÕES DA IA", PANEL);
        permissionsButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiPermissionsActivity.class)));
        LinearLayout.LayoutParams permissionParams = matchWrap();
        permissionParams.setMargins(0, dp(8), 0, 0);
        root.addView(permissionsButton, permissionParams);

        TextView budget = text(
            "ORÇAMENTO DESTE TESTE\n"
                + "Até 8 chamadas • 32 KiB de entrada total • 5 minutos.\n"
                + "Esses limites ficam travados junto com o Goal Lock.",
            13, MUTED, false);
        budget.setPadding(0, dp(16), 0, dp(8));
        root.addView(budget, matchWrap());

        feedback = text("Carregando ferramentas liberadas…", 13, MUTED, false);
        feedback.setPadding(0, dp(4), 0, dp(8));
        root.addView(feedback, matchWrap());

        createButton = button("CRIAR GOAL LOCK", ACCENT);
        createButton.setEnabled(false);
        createButton.setOnClickListener(v -> createGoalLock());
        root.addView(createButton, matchWrap());

        loadTools();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (toolsContainer != null && !busy) {
            loadTools();
        }
    }

    private void loadTools() {
        feedback.setText("Carregando ferramentas liberadas…");
        createButton.setEnabled(false);
        io.execute(() -> {
            try {
                List<LaboratoryAiToolController.Tool> tools =
                    LaboratoryAiToolController.listAvailable(this, projectId);
                runOnUiThread(() -> renderTools(tools));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    toolsContainer.removeAllViews();
                    toolChoices.clear();
                    feedback.setText(
                        "Falha ao carregar permissões da IA: "
                            + String.valueOf(error.getMessage()));
                    createButton.setEnabled(false);
                });
            }
        });
    }

    private void renderTools(List<LaboratoryAiToolController.Tool> tools) {
        if (!alive()) return;
        toolsContainer.removeAllViews();
        toolChoices.clear();

        if (tools.isEmpty()) {
            feedback.setText(
                "Nenhuma ferramenta STABLE está liberada para a IA neste projeto. "
                    + "Abra PERMISSÕES DA IA, libere ao menos uma ferramenta "
                    + "e volte para criar o Goal Lock.");
            createButton.setEnabled(false);
            return;
        }

        for (LaboratoryAiToolController.Tool tool : tools) {
            CheckBox choice = new CheckBox(this);
            choice.setText(
                tool.toolId + " • " + tool.version
                    + "\n" + tool.capabilities);
            choice.setTextColor(FG);
            choice.setTextSize(13);
            choice.setChecked(true);
            choice.setPadding(dp(4), dp(4), dp(4), dp(4));
            toolsContainer.addView(choice, matchWrap());
            toolChoices.add(new ToolChoice(tool, choice));
        }

        feedback.setText(
            tools.size()
                + " ferramenta(s) disponível(is) • revise o objetivo e crie o contrato");
        createButton.setEnabled(true);
    }

    private void createGoalLock() {
        if (busy) return;

        String goal = goalInput.getText().toString();
        List<String> selected = new ArrayList<>();
        for (ToolChoice choice : toolChoices) {
            if (choice.checkBox.isChecked()) {
                selected.add(choice.tool.toolId);
            }
        }

        if (goal.trim().isEmpty()) {
            feedback.setText("Escreva o objetivo exato antes de criar o Goal Lock.");
            goalInput.requestFocus();
            return;
        }
        if (goal.length() > LaboratoryAiTaskContractStore.MAX_GOAL_CHARS) {
            feedback.setText(
                "O objetivo ultrapassa "
                    + LaboratoryAiTaskContractStore.MAX_GOAL_CHARS
                    + " caracteres.");
            goalInput.requestFocus();
            return;
        }
        if (selected.isEmpty()) {
            feedback.setText(
                "Selecione ao menos uma ferramenta permitida para este contrato.");
            return;
        }

        LaboratoryAiTaskContractStore.Mode mode =
            learningMode.isChecked()
                ? LaboratoryAiTaskContractStore.Mode.LEARNING
                : LaboratoryAiTaskContractStore.Mode.CREATION;
        LaboratoryAiSessionController.Policy policy =
            new LaboratoryAiSessionController.Policy(
                selected,
                DEFAULT_MAX_INVOCATIONS,
                DEFAULT_MAX_TOTAL_INPUT_BYTES,
                DEFAULT_MAX_SESSION_MS);

        busy = true;
        setFormEnabled(false);
        feedback.setText("Criando contrato imutável…");

        io.execute(() -> {
            try {
                LaboratoryAiTaskContractStore.Contract contract =
                    LaboratoryAiTaskAdmission.createContract(
                        this, projectId, mode, goal, policy);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    setFormEnabled(true);
                    feedback.setText("Goal Lock criado e pronto para o planejador.");
                    setResult(RESULT_OK);
                    new AlertDialog.Builder(this)
                        .setTitle("Goal Lock criado")
                        .setMessage(
                            "Contrato: " + contract.contractId
                                + "\nModo: " + contract.mode.name()
                                + "\nFerramentas: " + contract.allowedToolIds
                                + "\nChamadas: " + contract.maxInvocations
                                + "\nEntrada total: "
                                + contract.maxTotalInputBytes + " bytes"
                                + "\nTempo: " + contract.maxSessionMs + " ms"
                                + "\n\nO objetivo foi preservado exatamente e "
                                + "o contrato ainda NÃO foi consumido.")
                        .setPositiveButton(
                            "VOLTAR",
                            (dialog, which) -> finish())
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    setFormEnabled(true);
                    feedback.setText(
                        "Goal Lock não foi criado: "
                            + String.valueOf(error.getMessage()));
                });
            }
        });
    }

    private void setFormEnabled(boolean enabled) {
        goalInput.setEnabled(enabled);
        creationMode.setEnabled(enabled);
        learningMode.setEnabled(enabled);
        permissionsButton.setEnabled(enabled);
        for (ToolChoice choice : toolChoices) {
            choice.checkBox.setEnabled(enabled);
        }
        createButton.setEnabled(enabled && !toolChoices.isEmpty());
    }

    private RadioButton radio(String label) {
        RadioButton button = new RadioButton(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(14);
        return button;
    }

    private Button button(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
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
        return Math.round(
            value * getResources().getDisplayMetrics().density);
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
