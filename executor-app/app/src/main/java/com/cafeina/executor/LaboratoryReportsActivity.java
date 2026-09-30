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
    private LaboratoryStableUseStore stableUses;
    private LaboratoryAiSessionStore aiSessions;
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

        Button approvalsButton = button("REVISAR APROVAÇÕES HUMANAS");
        approvalsButton.setOnClickListener(v ->
            startActivity(new Intent(this, LaboratoryApprovalActivity.class)));
        LinearLayout.LayoutParams approvalParams = matchWrap();
        approvalParams.setMargins(0, dp(10), 0, 0);
        root.addView(approvalsButton, approvalParams);

        Button aiPermissionsButton = button("PERMISSÕES DA IA");
        aiPermissionsButton.setOnClickListener(v ->
            startActivity(new Intent(this, LaboratoryAiPermissionsActivity.class)));
        LinearLayout.LayoutParams aiPermissionParams = matchWrap();
        aiPermissionParams.setMargins(0, dp(8), 0, 0);
        root.addView(aiPermissionsButton, aiPermissionParams);

        Button recoveryButton = button("RECUPERAR SESSÕES DA IA");
        recoveryButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiSessionRecoveryActivity.class)));
        LinearLayout.LayoutParams recoveryParams = matchWrap();
        recoveryParams.setMargins(0, dp(8), 0, 0);
        root.addView(recoveryButton, recoveryParams);

        Button liveSessionsButton = button("CONTROLAR SESSÕES AO VIVO");
        liveSessionsButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiLiveSessionActivity.class)));
        LinearLayout.LayoutParams liveSessionParams = matchWrap();
        liveSessionParams.setMargins(0, dp(8), 0, 0);
        root.addView(liveSessionsButton, liveSessionParams);

        Button taskContractsButton = button("CONTRATOS GOAL LOCK");
        taskContractsButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiTaskContractsActivity.class)));
        LinearLayout.LayoutParams taskContractParams = matchWrap();
        taskContractParams.setMargins(0, dp(8), 0, 0);
        root.addView(taskContractsButton, taskContractParams);

        Button testAgentReportsButton = button("RELATÓRIOS IA DE TESTE");
        testAgentReportsButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiTestAgentReportsActivity.class)));
        LinearLayout.LayoutParams testAgentReportParams = matchWrap();
        testAgentReportParams.setMargins(0, dp(8), 0, 0);
        root.addView(testAgentReportsButton, testAgentReportParams);

        Button testScenariosButton = button("CENÁRIOS IA DE TESTE");
        testScenariosButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiTestScenariosActivity.class)));
        LinearLayout.LayoutParams testScenarioParams = matchWrap();
        testScenarioParams.setMargins(0, dp(8), 0, 0);
        root.addView(testScenariosButton, testScenarioParams);

        Button aiDiagnosticsButton = button("DIAGNÓSTICO DAS IAS");
        aiDiagnosticsButton.setOnClickListener(v ->
            startActivity(new Intent(
                this, LaboratoryAiDiagnosticsActivity.class)));
        LinearLayout.LayoutParams aiDiagnosticsParams = matchWrap();
        aiDiagnosticsParams.setMargins(0, dp(8), 0, 0);
        root.addView(aiDiagnosticsButton, aiDiagnosticsParams);

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
            stableUses = new LaboratoryStableUseStore(getFilesDir(), projectId);
            aiSessions = new LaboratoryAiSessionStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir os relatórios: " + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryReportStore.Entry> items = reports.list();
                List<LaboratoryStableUseStore.Use> uses;
                String useProblem = null;
                try {
                    uses = stableUses.list();
                } catch (Exception error) {
                    uses = java.util.Collections.emptyList();
                    useProblem = "Auditoria STABLE indisponível: " + error.getMessage();
                }
                final List<LaboratoryStableUseStore.Use> stableUseItems = uses;
                final String stableUseWarning = useProblem;

                List<LaboratoryAiSessionStore.Summary> sessions;
                String sessionProblem = null;
                try {
                    sessions = aiSessions.list();
                } catch (Exception error) {
                    sessions = java.util.Collections.emptyList();
                    sessionProblem = "Auditoria de sessões indisponível: " + error.getMessage();
                }
                final List<LaboratoryAiSessionStore.Summary> sessionItems = sessions;
                final String sessionWarning = sessionProblem;
                runOnUiThread(() -> {
                    if (!alive()) return;
                    entries.removeAllViews();
                    feedback.setText(items.size() + " relatório(s) • "
                        + stableUseItems.size() + " uso(s) STABLE • "
                        + sessionItems.size() + " sessão(ões) IA • somente leitura");
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

                    TextView stableTitle = text("AUDITORIA DE USO STABLE", 17, FG, true);
                    stableTitle.setPadding(0, dp(18), 0, dp(4));
                    entries.addView(stableTitle, matchWrap());
                    entries.addView(text(
                        "Execuções do gate verificado. Entrada, saída e erros são "
                            + "preservados somente por hash.",
                        13, MUTED, false), matchWrap());
                    if (stableUseWarning != null) {
                        entries.addView(text(stableUseWarning, 14, FG, false), matchWrap());
                    } else if (stableUseItems.isEmpty()) {
                        entries.addView(text(
                            "Nenhuma ferramenta STABLE foi executada pelo gate.",
                            14, MUTED, false), matchWrap());
                    }
                    for (LaboratoryStableUseStore.Use use : stableUseItems) {
                        Button useButton = button(
                            use.toolId + " @ " + use.toolVersion + " • "
                                + (use.usable ? "UTILIZÁVEL" : "BLOQUEADA/FALHOU")
                                + "\n" + time(use.startedAtEpochMs)
                                + "  |  " + use.durationMs + " ms");
                        useButton.setAllCaps(false);
                        useButton.setTextSize(14);
                        useButton.setGravity(android.view.Gravity.START
                            | android.view.Gravity.CENTER_VERTICAL);
                        useButton.setBackgroundTintList(ColorStateList.valueOf(PANEL));
                        useButton.setOnClickListener(v -> showStableUse(use));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, dp(8), 0, 0);
                        entries.addView(useButton, params);
                    }

                    TextView sessionTitle = text("SESSÕES DA IA", 17, FG, true);
                    sessionTitle.setPadding(0, dp(18), 0, dp(4));
                    entries.addView(sessionTitle, matchWrap());
                    entries.addView(text(
                        "Histórico persistente de orçamento e controle da sessão. "
                            + "Entradas e saídas brutas não são armazenadas aqui.",
                        13, MUTED, false), matchWrap());
                    if (sessionWarning != null) {
                        entries.addView(text(sessionWarning, 14, FG, false), matchWrap());
                    } else if (sessionItems.isEmpty()) {
                        entries.addView(text(
                            "Nenhuma sessão da IA foi iniciada neste projeto.",
                            14, MUTED, false), matchWrap());
                    }
                    for (LaboratoryAiSessionStore.Summary session : sessionItems) {
                        Button sessionButton = button(
                            "SESSÃO • " + session.state
                                + "\n" + time(session.startedAtEpochMs)
                                + "  |  " + session.invocationsUsed + "/"
                                + session.maxInvocations + " chamadas");
                        sessionButton.setAllCaps(false);
                        sessionButton.setTextSize(14);
                        sessionButton.setGravity(android.view.Gravity.START
                            | android.view.Gravity.CENTER_VERTICAL);
                        sessionButton.setBackgroundTintList(ColorStateList.valueOf(PANEL));
                        sessionButton.setOnClickListener(v -> showAiSession(session));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, dp(8), 0, 0);
                        entries.addView(sessionButton, params);
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
            if (report.has("toolInputSha256")) {
                body.append("\nSHA-256 da entrada da ferramenta: ")
                    .append(report.optString("toolInputSha256"));
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

    private void showStableUse(LaboratoryStableUseStore.Use use) {
        String details = "Ferramenta: " + use.toolId
            + "\nVersão: " + use.toolVersion
            + "\nStatus do worker: " + use.workerStatus
            + "\nResultado utilizável: " + (use.usable ? "SIM" : "NÃO")
            + "\nSeleção STABLE permaneceu válida: "
            + (use.selectionVerified ? "SIM" : "NÃO")
            + "\nInício: " + time(use.startedAtEpochMs)
            + "\nDuração: " + use.durationMs + " ms"
            + "\nWorker UID: " + use.workerUid
            + "\nEvento STABLE: " + use.activationEventId
            + " #" + use.activationSequence
            + "\nSnapshot: " + use.snapshotId
            + "\nArtefato esperado SHA-256: " + use.artifactSha256
            + "\nFonte executada SHA-256: " + use.executedSourceSha256
            + "\nEntrada esperada SHA-256: " + use.inputSha256
            + "\nEntrada executada SHA-256: " + use.executedInputSha256
            + "\nRetorno SHA-256: " + use.firstReturnSha256
            + "\nSaída SHA-256: " + use.outputSha256
            + "\nErro SHA-256: " + use.errorSha256
            + "\nExecução: " + use.runId
            + "\n\nO texto da fonte, entrada, saída, retorno e erro não é "
            + "persistido neste recibo.";
        TextView view = text(details, 13, FG, false);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextIsSelectable(true);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);
        new AlertDialog.Builder(this)
            .setTitle("Uso STABLE • somente leitura")
            .setView(scroll)
            .setPositiveButton("FECHAR", null)
            .show();
    }

    private void showAiSession(LaboratoryAiSessionStore.Summary session) {
        String details = "Sessão: " + session.sessionId
            + "\nEstado: " + session.state
            + "\nInício: " + time(session.startedAtEpochMs)
            + "\nÚltimo evento: " + time(session.lastEventAtEpochMs)
            + "\nFerramentas permitidas: " + session.allowedToolIds
            + "\nChamadas: " + session.invocationsUsed + " / "
            + session.maxInvocations
            + "\nEntrada acumulada: " + session.inputBytesUsed + " / "
            + session.maxTotalInputBytes + " bytes"
            + "\nDuração máxima: " + session.maxSessionMs + " ms"
            + "\nEventos persistidos: " + session.eventCount
            + "\n\nEste histórico não contém tool_input, retorno ou saída bruta.";
        TextView view = text(details, 13, FG, false);
        view.setTypeface(Typeface.MONOSPACE);
        view.setTextIsSelectable(true);
        view.setPadding(dp(14), dp(12), dp(14), dp(12));
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);
        new AlertDialog.Builder(this)
            .setTitle("Sessão da IA • somente leitura")
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
        if (reports != null && stableUses != null && aiSessions != null) refresh();
    }

    @Override
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
