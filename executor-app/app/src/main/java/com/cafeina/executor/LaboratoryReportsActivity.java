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
            refresh();
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir os relatórios: " + error.getMessage());
        }
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryReportStore.Entry> items = reports.list();
                runOnUiThread(() -> {
                    if (!alive()) return;
                    entries.removeAllViews();
                    feedback.setText(items.size() + " relatório(s) • somente leitura");
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
    protected void onDestroy() {
        io.shutdownNow();
        super.onDestroy();
    }
}
