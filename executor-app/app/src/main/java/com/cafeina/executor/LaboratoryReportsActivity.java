package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.DateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Read-only laboratory report viewer. No tool execution, generated code input,
 * approval, promotion or deletion controls are exposed to the end user here.
 */
public final class LaboratoryReportsActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LaboratoryReportStore reports;
    private LaboratoryToolRegistry registry;
    private LaboratoryHumanApprovalStore approvals;
    private LaboratorySuiteStore suites;
    private TextView feedback;
    private LinearLayout entries;

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

        Button back = button("← VOLTAR AO SISTEMA");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("RELATÓRIOS • LABORATÓRIO", 21, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());
        root.addView(text(
            "Ferramentas e testes são internos à IA. Aqui você consulta resultados, "
                + "falhas e evidências; esta tela não executa nem modifica ferramentas.",
            14, MUTED, false), matchWrap());

        Button review = button("REVISAR APROVAÇÕES HUMANAS");
        review.setOnClickListener(v ->
            startActivity(new Intent(this, LaboratoryApprovalActivity.class)));
        LinearLayout.LayoutParams reviewParams = matchWrap();
        reviewParams.setMargins(0, dp(10), 0, 0);
        root.addView(review, reviewParams);

        String projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        feedback = text("Carregando relatórios…", 14, MUTED, false);
        feedback.setPadding(0, dp(14), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        try {
            reports = new LaboratoryReportStore(getFilesDir(), projectId);
            registry = new LaboratoryToolRegistry(getFilesDir(), projectId);
            approvals = new LaboratoryHumanApprovalStore(getFilesDir(), projectId);
            suites = new LaboratorySuiteStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir os relatórios: " + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryReportStore.Entry> items = reports.list();
                List<LaboratoryToolRegistry.Tool> catalog;
                String registryProblem = null;
                try {
                    catalog = registry.list();
                } catch (Exception error) {
                    // A damaged registry must not hide unrelated test reports.
                    catalog = java.util.Collections.emptyList();
                    registryProblem = "Catálogo de ferramentas indisponível: "
                        + error.getMessage();
                }
                final List<LaboratoryToolRegistry.Tool> toolItems = catalog;
                final String registryWarning = registryProblem;
                final java.util.Set<String> approvedVersions = new java.util.HashSet<>();
                String approvalProblem = null;
                try {
                    for (LaboratoryHumanApprovalStore.Approval approval : approvals.list()) {
                        approvedVersions.add(approval.toolId + "@" + approval.version);
                    }
                } catch (Exception error) {
                    approvalProblem = "Aprovações indisponíveis: " + error.getMessage();
                }
                final String approvalWarning = approvalProblem;
                List<LaboratorySuiteStore.Summary> suiteHistory;
                String suiteProblem = null;
                try {
                    suiteHistory = suites.list();
                } catch (Exception error) {
                    suiteHistory = java.util.Collections.emptyList();
                    suiteProblem = "Histórico de lotes indisponível: " + error.getMessage();
                }
                final List<LaboratorySuiteStore.Summary> suiteItems = suiteHistory;
                final String suiteWarning = suiteProblem;
                runOnUiThread(() -> {
                    if (!alive()) return;
                    entries.removeAllViews();
                    feedback.setText(items.size() + " relatório(s) • " + toolItems.size()
                        + " versão(ões) de ferramenta • somente leitura");

                    TextView toolsTitle = text("FERRAMENTAS INTERNAS", 17, FG, true);
                    toolsTitle.setPadding(0, dp(12), 0, dp(4));
                    entries.addView(toolsTitle, matchWrap());
                    entries.addView(text(
                        "EXPERIMENTAL: não aprovada. CANDIDATA: aguardando revisão "
                            + "e aprovação humana. Nenhuma pode ativar uma versão estável.",
                        13, MUTED, false), matchWrap());
                    if (registryWarning != null) {
                        entries.addView(text(registryWarning, 14, FG, false), matchWrap());
                    }
                    if (approvalWarning != null) {
                        entries.addView(text(approvalWarning, 14, FG, false), matchWrap());
                    }
                    if (registryWarning == null && toolItems.isEmpty()) {
                        entries.addView(text(
                            "Nenhuma ferramenta candidata registrada neste projeto.",
                            14, MUTED, false), matchWrap());
                    }
                    for (LaboratoryToolRegistry.Tool tool : toolItems) {
                        boolean approved = approvedVersions.contains(tool.id + "@" + tool.version);
                        String stateLabel = approved
                            ? "APROVADA PELO USUÁRIO • NÃO ATIVA"
                            : tool.state == LaboratoryToolRegistry.State.CANDIDATE
                                ? "CANDIDATA • NÃO APROVADA" : "EXPERIMENTAL";
                        Button entryButton = button(tool.id + " @ " + tool.version
                            + "\n" + stateLabel);
                        entryButton.setAllCaps(false);
                        entryButton.setTextSize(14);
                        entryButton.setGravity(android.view.Gravity.START
                            | android.view.Gravity.CENTER_VERTICAL);
                        entryButton.setBackgroundTintList(ColorStateList.valueOf(PANEL));
                        entryButton.setOnClickListener(v -> showTool(tool, approved));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, dp(8), 0, 0);
                        entries.addView(entryButton, params);
                    }

                    TextView suitesTitle = text("LOTES E REGRESSÕES", 17, FG, true);
                    suitesTitle.setPadding(0, dp(18), 0, dp(4));
                    entries.addView(suitesTitle, matchWrap());
                    entries.addView(text(
                        "BATCH: casos em lote. REPLAY: repetição dos mesmos casos. "
                            + "STRESS: três execuções idênticas. REGRESSION: comparação "
                            + "com um relatório anterior do projeto.",
                        13, MUTED, false), matchWrap());
                    if (suiteWarning != null) {
                        entries.addView(text(suiteWarning, 14, FG, false), matchWrap());
                    } else if (suiteItems.isEmpty()) {
                        entries.addView(text(
                            "Ainda não há lotes registrados neste projeto.",
                            14, MUTED, false), matchWrap());
                    }
                    for (LaboratorySuiteStore.Summary suite : suiteItems) {
                        Button summary = button(suite.mode + " • " + suite.status.name()
                            + "\n" + time(suite.startedAtEpochMs) + "  |  "
                            + suite.passed + " passou / " + suite.failed + " falhou");
                        summary.setAllCaps(false);
                        summary.setTextSize(14);
                        summary.setGravity(android.view.Gravity.START
                            | android.view.Gravity.CENTER_VERTICAL);
                        summary.setBackgroundTintList(ColorStateList.valueOf(PANEL));
                        summary.setOnClickListener(v -> showSuite(suite));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, dp(8), 0, 0);
                        entries.addView(summary, params);
                    }

                    TextView reportTitle = text("HISTÓRICO DE TESTES", 17, FG, true);
                    reportTitle.setPadding(0, dp(18), 0, dp(4));
                    entries.addView(reportTitle, matchWrap());
                    if (items.isEmpty()) {
                        entries.addView(text(
                            "Ainda não há relatórios. Eles aparecerão quando as ferramentas "
                                + "internas forem testadas. A IA principal ainda não está integrada.",
                            15, MUTED, false), matchWrap());
                    }
                    for (LaboratoryReportStore.Entry entry : items) {
                        Button reportButton = button(
                            entry.toolId + " • " + entry.status + "\n"
                                + time(entry.startedAtEpochMs)
                                + "  |  " + entry.passed + " passou / "
                                + entry.failed + " falhou");
                        reportButton.setAllCaps(false);
                        reportButton.setTextSize(14);
                        reportButton.setGravity(android.view.Gravity.START
                            | android.view.Gravity.CENTER_VERTICAL);
                        reportButton.setBackgroundTintList(ColorStateList.valueOf(PANEL));
                        reportButton.setOnClickListener(v -> showReport(entry));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, dp(8), 0, 0);
                        entries.addView(reportButton, params);
                    }
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha na leitura dos relatórios: " + error.getMessage());
                });
            }
        });
    }

    private void showTool(LaboratoryToolRegistry.Tool tool, boolean approved) {
        String stage = approved ? "APROVADA PELO USUÁRIO • AINDA NÃO ATIVA"
            : tool.state == LaboratoryToolRegistry.State.CANDIDATE
                ? "CANDIDATA PARA REVISÃO • NÃO APROVADA"
                : "EXPERIMENTAL • NÃO APROVADA";
        String details = "Ferramenta: " + tool.id
            + "\nVersão: " + tool.version
            + "\nEstado: " + stage
            + "\nCapacidade: " + tool.capability
            + "\nLimite de execução: " + tool.timeoutMs + " ms"
            + "\nCriada: " + time(tool.createdAtEpochMs)
            + "\nSHA-256 da fonte: " + tool.sourceSha256
            + "\nSHA-256 do manifesto: " + tool.manifestSha256
            + "\nSnapshot: " + tool.snapshotId
            + (tool.evidenceRunId.isEmpty() ? "\nSem teste aprovado para revisão"
                : "\nRelatório de evidência: " + tool.evidenceRunId)
            + "\n\n" + (approved
                ? "A aprovação humana está registrada, mas não existe ativação STABLE nesta etapa."
                : "O registro não executa ferramentas nem altera versões estáveis.");
        TextView text = text(details, 13, FG, false);
        text.setTypeface(Typeface.MONOSPACE);
        text.setTextIsSelectable(true);
        text.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(text);
        new AlertDialog.Builder(this)
            .setTitle("Versão de ferramenta • somente leitura")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private void showSuite(LaboratorySuiteStore.Summary suite) {
        StringBuilder body = new StringBuilder()
            .append("Modalidade: ").append(suite.mode)
            .append("\nEstado: ").append(suite.status.name())
            .append("\nMotivo: ").append(suite.reason)
            .append("\nInício: ").append(time(suite.startedAtEpochMs))
            .append("\nFim: ").append(time(suite.completedAtEpochMs))
            .append("\nPlanejados: ").append(suite.requested)
            .append("\nAprovados: ").append(suite.passed)
            .append("\nFalharam: ").append(suite.failed)
            .append("\nPlano SHA-256: ").append(suite.planSha256)
            .append("\nLote: ").append(suite.suiteId);
        if (suite.status == LaboratorySuiteStore.Status.RUNNING_OR_INTERRUPTED) {
            body.append("\n\nHá um início registrado sem conclusão. "
                + "O teste pode estar em andamento ou ter sido interrompido; "
                + "ele NÃO é considerado aprovado.");
        }
        if (!suite.reportIds.isEmpty()) {
            body.append("\n\nRelatórios individuais:");
            for (String id : suite.reportIds) body.append("\n").append(id);
        }
        TextView details = text(body.toString(), 13, FG, false);
        details.setTypeface(Typeface.MONOSPACE);
        details.setTextIsSelectable(true);
        details.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(details);
        new AlertDialog.Builder(this)
            .setTitle("Lote do laboratório • somente leitura")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private void showReport(LaboratoryReportStore.Entry entry) {
        StringBuilder body = new StringBuilder()
            .append("Ferramenta: ").append(entry.toolId)
            .append("\nVersão: ").append(entry.toolVersion)
            .append("\nResultado: ").append(entry.status)
            .append("\nInício: ").append(time(entry.startedAtEpochMs))
            .append("\nSucessos: ").append(entry.passed)
            .append("  |  Falhas: ").append(entry.failed)
            .append("\nExecução: ").append(entry.runId);

        try {
            JSONObject report = new JSONObject(entry.reportText);
            body.append("\nEstado: ").append(report.optString("stage"))
                .append("\nSeed: ").append(report.optLong("seed"))
                .append("\nDuração: ").append(report.optLong("durationMs")).append(" ms")
                .append("\nSHA-256 do lote: ").append(report.optString("candidateBatchSha256"));
            if (report.has("environmentSha256")) {
                body.append("\nSHA-256 do ambiente de teste: ")
                    .append(report.optString("environmentSha256"));
            }
            if (report.has("candidateSnapshotId")) {
                body.append("\nSnapshot de recuperação: ")
                    .append(report.optString("candidateSnapshotId"))
                    .append("\nIntegridade do snapshot no teste: ")
                    .append(report.optBoolean("snapshotVerified") ? "CONFIRMADA" : "FALHOU");
            }
            JSONArray checks = report.optJSONArray("checks");
            if (checks != null) {
                for (int i = 0; i < checks.length(); i++) {
                    JSONObject check = checks.optJSONObject(i);
                    if (check == null) continue;
                    body.append("\n\n").append(check.optBoolean("passed") ? "PASSOU" : "FALHOU")
                        .append(" • ").append(check.optString("name"))
                        .append("\nMotivo: ").append(check.optString("reason"))
                        .append("\nEsperado: ").append(check.optString("expectedOutput"))
                        .append("\nObtido: ").append(check.optString("actualOutput"))
                        .append("\nFonte SHA-256: ").append(check.optString("inputSha256"));
                }
            }
        } catch (Exception corrupt) {
            body.append("\n\nRelatório indisponível ou corrompido:\n")
                .append(entry.reportText);
        }

        ScrollView scroll = new ScrollView(this);
        TextView details = text(body.toString(), 13, FG, false);
        details.setTypeface(Typeface.MONOSPACE);
        details.setTextIsSelectable(true);
        details.setPadding(dp(16), dp(12), dp(16), dp(12));
        scroll.addView(details);
        new AlertDialog.Builder(this)
            .setTitle("Relatório do laboratório")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private static String time(long epochMs) {
        if (epochMs <= 0) return "Data indisponível";
        return DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT,
            new Locale("pt", "BR")).format(new Date(epochMs));
    }

    private boolean alive() { return !isFinishing() && !isDestroyed(); }

    private Button button(String label) {
        Button result = new Button(this);
        result.setText(label);
        result.setTextSize(14);
        result.setTextColor(FG);
        result.setBackgroundTintList(ColorStateList.valueOf(ACCENT));
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
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (reports != null && registry != null && approvals != null && suites != null) refresh();
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
