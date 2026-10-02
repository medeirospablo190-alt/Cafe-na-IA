package com.cafeina.executor;

import android.app.Activity;
import android.content.Intent;
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

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private bootstrap Workshop for the first isolated diagnostic tool.
 *
 * This screen may create an EXPERIMENTAL artifact, run deterministic candidate
 * tests and qualify CANDIDATE evidence. It cannot activate STABLE or grant AI
 * permission; those remain separate explicit user decisions.
 */
public final class LaboratoryToolWorkshopActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io =
        Executors.newSingleThreadExecutor();

    private LinearLayout content;
    private TextView feedback;
    private Button cancelSuiteButton;
    private String projectId;
    private volatile boolean busy;
    private volatile LaboratoryCandidateTestSuiteRunner.Control
        activeSuiteControl;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        projectId = getSharedPreferences(
            "cafeina_workspace",
            MODE_PRIVATE)
            .getString("project_id", "");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR", PANEL);
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text(
            "WORKSHOP • FERRAMENTA DIAGNÓSTICA",
            20,
            FG,
            true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Este primeiro template serve apenas para provar o ciclo completo "
                + "do laboratório. Ele recebe tool_input e devolve o mesmo "
                + "valor dentro do worker Luau isolado. Não recebe filesystem, "
                + "rede, aprovações, snapshots ou acesso ao projeto.",
            14,
            MUTED,
            false), matchWrap());

        root.addView(text(
            "Fluxo obrigatório: EXPERIMENTAL → suíte determinística → "
                + "CANDIDATE → aprovação humana → STABLE → permissão separada "
                + "para a IA. Esta tela não pula nenhuma dessas etapas.",
            13,
            MUTED,
            false), paddedTop(dp(8)));

        feedback = text(
            "Carregando estado do Workshop…",
            13,
            MUTED,
            false);
        feedback.setPadding(0, dp(12), 0, dp(8));
        root.addView(feedback, matchWrap());

        cancelSuiteButton = button("CANCELAR SUÍTE", PANEL);
        cancelSuiteButton.setVisibility(android.view.View.GONE);
        cancelSuiteButton.setOnClickListener(v -> {
            LaboratoryCandidateTestSuiteRunner.Control control =
                activeSuiteControl;
            if (control != null) {
                control.cancel();
                feedback.setText(
                    "Cancelamento solicitado à suíte…");
                cancelSuiteButton.setEnabled(false);
            }
        });
        LinearLayout.LayoutParams cancelParams = matchWrap();
        cancelParams.setMargins(0, 0, 0, dp(8));
        root.addView(cancelSuiteButton, cancelParams);

        ScrollView scroll = new ScrollView(this);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content);
        root.addView(
            scroll,
            new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f));
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
    }

    private void refresh() {
        if (busy) return;
        feedback.setText("Validando ferramenta diagnóstica…");
        io.execute(() -> {
            try {
                LaboratoryDiagnosticEchoTool.State state =
                    LaboratoryDiagnosticEchoTool.inspect(
                        getFilesDir(),
                        projectId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    render(state);
                });
            } catch (Exception error) {
                final String reason =
                    String.valueOf(error.getMessage());
                runOnUiThread(() -> {
                    if (!alive()) return;
                    content.removeAllViews();
                    feedback.setText(
                        "Falha ao validar Workshop: " + reason);
                });
            }
        });
    }

    private void render(LaboratoryDiagnosticEchoTool.State state) {
        content.removeAllViews();

        String stage = !state.registered
            ? "NÃO REGISTRADA"
            : state.stage == null
                ? "ESTADO DESCONHECIDO"
                : state.stage.name();

        feedback.setText(
            LaboratoryDiagnosticEchoTool.TOOL_ID
                + " @ "
                + LaboratoryDiagnosticEchoTool.VERSION
                + " • " + stage);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackgroundTintList(
            ColorStateList.valueOf(PANEL));

        TextView details = text(
            "ID: " + LaboratoryDiagnosticEchoTool.TOOL_ID
                + "
Versão: "
                + LaboratoryDiagnosticEchoTool.VERSION
                + "
Artefato SHA-256: "
                + LaboratoryDiagnosticEchoTool.sourceSha256()
                + "
Execução: Luau isolado, sem filesystem"
                + "
Entrada máxima: "
                + LaboratoryDiagnosticEchoTool.MAX_INPUT_BYTES
                + " bytes"
                + "
Timeout: "
                + LaboratoryDiagnosticEchoTool.MAX_RUNTIME_MS
                + " ms"
                + "
Registro: "
                + (state.registered ? "SIM" : "NÃO")
                + "
Artefato vinculado: "
                + (state.artifactBound ? "SIM" : "NÃO")
                + "
Estágio: " + stage,
            13,
            FG,
            false);
        details.setTextIsSelectable(true);
        card.addView(details, matchWrap());

        if (!state.registered) {
            addCardButton(
                card,
                "PREPARAR TEMPLATE EXPERIMENTAL",
                this::prepareExperimental);
        } else if (state.stage
                == LaboratoryToolRegistry.Stage.EXPERIMENTAL) {
            if (!state.artifactBound) {
                addCardButton(
                    card,
                    "REPARAR VÍNCULO DO TEMPLATE",
                    this::prepareExperimental);
            } else {
                addCardButton(
                    card,
                    "RODAR SUÍTE ISOLADA E QUALIFICAR CANDIDATA",
                    this::runCandidateSuite);
            }
        } else if (state.stage
                == LaboratoryToolRegistry.Stage.CANDIDATE) {
            TextView note = text(
                "A suíte passou e a ferramenta é CANDIDATE. Ela ainda NÃO "
                    + "é executável pela IA. A promoção para STABLE exige sua "
                    + "aprovação autenticada.",
                13,
                MUTED,
                false);
            note.setPadding(0, dp(8), 0, 0);
            card.addView(note, matchWrap());

            addCardButton(
                card,
                "ABRIR APROVAÇÃO HUMANA",
                () -> startActivity(new Intent(
                    this,
                    LaboratoryApprovalActivity.class)));
        } else if (state.stage
                == LaboratoryToolRegistry.Stage.STABLE) {
            TextView note = text(
                "A ferramenta já é STABLE. Isso ainda não significa que a IA "
                    + "possa usá-la: a autorização da IA é separada.",
                13,
                MUTED,
                false);
            note.setPadding(0, dp(8), 0, 0);
            card.addView(note, matchWrap());

            addCardButton(
                card,
                "ABRIR PERMISSÕES DA IA",
                () -> startActivity(new Intent(
                    this,
                    LaboratoryAiPermissionsActivity.class)));
        }

        addCardButton(
            card,
            "ABRIR RELATÓRIOS DO LABORATÓRIO",
            () -> startActivity(new Intent(
                this,
                LaboratoryReportsActivity.class)));

        LinearLayout.LayoutParams cardParams = matchWrap();
        cardParams.setMargins(0, dp(8), 0, dp(8));
        content.addView(card, cardParams);

    }

    private void prepareExperimental() {
        if (busy) return;
        busy = true;
        feedback.setText(
            "Preparando descriptor, snapshot e artefato EXPERIMENTAL…");
        io.execute(() -> {
            try {
                LaboratoryDiagnosticEchoTool.State prepared =
                    LaboratoryDiagnosticEchoTool.prepareExperimental(
                        getFilesDir(),
                        projectId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Template EXPERIMENTAL preparado. Nenhum teste "
                            + "foi executado automaticamente.");
                    render(prepared);
                });
            } catch (Exception error) {
                final String reason =
                    String.valueOf(error.getMessage());
                runOnUiThread(() -> {
                    if (!alive()) return;
                    busy = false;
                    feedback.setText(
                        "Não consegui preparar o template: " + reason);
                    refresh();
                });
            }
        });
    }

    private void runCandidateSuite() {
        if (busy) return;

        busy = true;
        LaboratoryCandidateTestSuiteRunner.Control control =
            new LaboratoryCandidateTestSuiteRunner.Control();
        activeSuiteControl = control;
        cancelSuiteButton.setEnabled(true);
        cancelSuiteButton.setVisibility(android.view.View.VISIBLE);
        feedback.setText(
            "Suíte isolada iniciada • aguardando primeiro caso…");

        try {
            LaboratoryCandidateTestSuiteRunner.run(
                this,
                projectId,
                LaboratoryDiagnosticEchoTool.TOOL_ID,
                LaboratoryDiagnosticEchoTool.VERSION,
                LaboratoryDiagnosticEchoTool.suiteCases(),
                control,
                new LaboratoryCandidateTestSuiteRunner.Observer() {
                    @Override
                    public void onSuiteReady(
                            String toolId,
                            String version,
                            int totalCases) {
                        updateFeedback(
                            "Suíte pronta • "
                                + totalCases + " caso(s)");
                    }

                    @Override
                    public void onCaseStarted(
                            int index,
                            int total,
                            LaboratoryCandidateTestSuiteRunner.TestCase testCase) {
                        updateFeedback(
                            "Testando " + index + "/" + total
                                + " • " + testCase.name);
                    }

                    @Override
                    public void onCaseFinished(
                            int index,
                            int total,
                            LaboratoryCandidateTestSuiteRunner.CaseResult result) {
                        updateFeedback(
                            "Caso " + index + "/" + total
                                + " • " + result.name
                                + " • "
                                + (result.passed ? "PASSOU" : "FALHOU")
                                + " • " + result.durationMs + " ms");
                    }
                },
                (result, failure) -> {
                    if (!alive()) return;
                    activeSuiteControl = null;
                    cancelSuiteButton.setVisibility(android.view.View.GONE);
                    cancelSuiteButton.setEnabled(true);

                    if (failure != null) {
                        busy = false;
                        feedback.setText(
                            "Suíte não concluiu: "
                                + String.valueOf(failure.getMessage()));
                        refresh();
                        return;
                    }
                    if (result == null) {
                        busy = false;
                        feedback.setText(
                            "Suíte terminou sem resultado auditável.");
                        refresh();
                        return;
                    }
                    if (!result.qualifiesRequiredEvidence()) {
                        busy = false;
                        feedback.setText(
                            "Suíte terminou em " + result.status
                                + " • " + result.passed + "/"
                                + result.totalCases + " passaram. "
                                + "A ferramenta continua EXPERIMENTAL.");
                        refresh();
                        return;
                    }

                    feedback.setText(
                        "Suíte passou • qualificando CANDIDATE com as "
                            + "evidências persistidas…");
                    io.execute(() -> {
                        try {
                            LaboratoryDiagnosticEchoTool.State qualified =
                                LaboratoryDiagnosticEchoTool.qualifyCandidate(
                                    getFilesDir(),
                                    projectId,
                                    result);
                            runOnUiThread(() -> {
                                if (!alive()) return;
                                busy = false;
                                feedback.setText(
                                    "CANDIDATE qualificada. A promoção para "
                                        + "STABLE continua aguardando sua "
                                        + "aprovação.");
                                render(qualified);
                            });
                        } catch (Exception error) {
                            final String reason =
                                String.valueOf(error.getMessage());
                            runOnUiThread(() -> {
                                if (!alive()) return;
                                busy = false;
                                feedback.setText(
                                    "A suíte passou, mas a qualificação "
                                        + "CANDIDATE falhou: " + reason);
                                refresh();
                            });
                        }
                    });
                });
        } catch (Exception error) {
            activeSuiteControl = null;
            cancelSuiteButton.setVisibility(android.view.View.GONE);
            cancelSuiteButton.setEnabled(true);
            busy = false;
            feedback.setText(
                "Não consegui iniciar a suíte: "
                    + String.valueOf(error.getMessage()));
            refresh();
        }
    }

    private void updateFeedback(String value) {
        runOnUiThread(() -> {
            if (alive()) feedback.setText(value);
        });
    }

    private void addCardButton(
            LinearLayout card,
            String label,
            Runnable action) {
        Button button = button(label, ACCENT);
        button.setAllCaps(false);
        button.setOnClickListener(v -> {
            if (action != null) action.run();
        });
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, 0);
        card.addView(button, params);
    }

    private Button button(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(13);
        button.setGravity(Gravity.CENTER);
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

    private LinearLayout.LayoutParams paddedTop(int top) {
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, top, 0, 0);
        return params;
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
        LaboratoryCandidateTestSuiteRunner.Control control =
            activeSuiteControl;
        if (control != null) control.cancel();
        io.shutdownNow();
        super.onDestroy();
    }
}
