package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
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
 * The only current UI path that records a human approval decision.
 *
 * It never executes a tool and never activates STABLE. Android device
 * credential confirmation is required before the create-only approval receipt.
 */
public final class LaboratoryApprovalActivity extends Activity {
    private static final int REQUEST_DEVICE_CREDENTIAL = 4107;
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private LinearLayout entries;
    private TextView feedback;
    private LaboratoryToolRegistry registry;
    private LaboratoryHumanApprovalStore approvals;
    private String pendingToolId;
    private String pendingVersion;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        if (state != null) {
            pendingToolId = state.getString("pending_tool_id");
            pendingVersion = state.getString("pending_version");
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR AOS RELATÓRIOS");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("APROVAÇÃO HUMANA • LABORATÓRIO", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());
        root.addView(text(
            "Aprovar aqui não executa nem ativa a ferramenta. A decisão apenas "
                + "autoriza essa versão, com essa evidência, para uma futura etapa "
                + "de ativação estável. A IA não possui este controle.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando versões candidatas…", 14, MUTED, false);
        feedback.setPadding(0, dp(12), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        String projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        try {
            registry = new LaboratoryToolRegistry(getFilesDir(), projectId);
            approvals = new LaboratoryHumanApprovalStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir a área de aprovação: "
                + error.getMessage());
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putString("pending_tool_id", pendingToolId);
        outState.putString("pending_version", pendingVersion);
        super.onSaveInstanceState(outState);
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryToolRegistry.Tool> tools = registry.list();
                List<LaboratoryToolRegistry.Tool> candidates = new ArrayList<>();
                for (LaboratoryToolRegistry.Tool tool : tools) {
                    if (tool.state == LaboratoryToolRegistry.State.CANDIDATE) {
                        candidates.add(tool);
                    }
                }
                runOnUiThread(() -> render(candidates));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao validar versões: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryToolRegistry.Tool> candidates) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(candidates.size() + " candidata(s) com teste válido");
        if (candidates.isEmpty()) {
            entries.addView(text(
                "Nenhuma ferramenta aguarda sua revisão neste projeto.",
                14, MUTED, false), matchWrap());
            return;
        }
        for (LaboratoryToolRegistry.Tool tool : candidates) {
            final boolean approved;
            try {
                approved = approvals.isApproved(tool.id, tool.version);
            } catch (Exception invalidReceipt) {
                TextView warning = text(tool.id + " @ " + tool.version
                    + "\nAPROVAÇÃO INCONSISTENTE: " + invalidReceipt.getMessage(),
                    13, FG, true);
                warning.setPadding(dp(12), dp(12), dp(12), dp(12));
                entries.addView(warning, matchWrap());
                continue;
            }

            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            TextView info = text(tool.id + " @ " + tool.version + "\n"
                + (approved ? "APROVADA PELO USUÁRIO • NÃO ATIVA"
                    : "CANDIDATA • AGUARDANDO SUA DECISÃO")
                + "\nEvidência: " + tool.evidenceRunId
                + "\nFonte SHA-256: " + tool.sourceSha256,
                13, approved ? MUTED : FG, true);
            info.setTextIsSelectable(true);
            card.addView(info, matchWrap());

            if (!approved) {
                Button approve = button("REVISAR E APROVAR");
                approve.setOnClickListener(v -> confirm(tool));
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(8), 0, 0);
                card.addView(approve, params);
            } else {
                TextView note = text(
                    "A aprovação foi registrada, mas a versão ainda não pode "
                        + "se instalar, executar automaticamente ou virar STABLE.",
                    12, MUTED, false);
                note.setPadding(0, dp(6), 0, 0);
                card.addView(note, matchWrap());
            }
            LinearLayout.LayoutParams params = matchWrap();
            params.setMargins(0, dp(8), 0, 0);
            entries.addView(card, params);
        }
    }

    private void confirm(LaboratoryToolRegistry.Tool tool) {
        String message = "Ferramenta: " + tool.id
            + "\nVersão: " + tool.version
            + "\nCapacidade: " + tool.capability
            + "\nLimite: " + tool.timeoutMs + " ms"
            + "\nEvidência: " + tool.evidenceRunId
            + "\nFonte SHA-256: " + tool.sourceSha256
            + "\n\nIsto registra apenas sua aprovação para uma futura ativação. "
            + "Nenhuma ferramenta será executada agora.";
        new AlertDialog.Builder(this)
            .setTitle("Revisar candidata")
            .setMessage(message)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CONFIRMAR IDENTIDADE", (dialog, which) ->
                requestCredential(tool))
            .show();
    }

    private void requestCredential(LaboratoryToolRegistry.Tool tool) {
        KeyguardManager keyguard =
            (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (keyguard == null || !keyguard.isDeviceSecure()) {
            new AlertDialog.Builder(this)
                .setTitle("Bloqueio de tela necessário")
                .setMessage("Configure PIN, senha ou outro bloqueio seguro do Android "
                    + "antes de aprovar uma ferramenta.")
                .setPositiveButton("OK", null)
                .show();
            return;
        }
        Intent credential = keyguard.createConfirmDeviceCredentialIntent(
            "Aprovar ferramenta da CAFEÍNA",
            "Confirme o bloqueio do aparelho para registrar esta decisão.");
        if (credential == null) {
            feedback.setText("O Android não disponibilizou a confirmação de identidade.");
            return;
        }
        pendingToolId = tool.id;
        pendingVersion = tool.version;
        startActivityForResult(credential, REQUEST_DEVICE_CREDENTIAL);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_DEVICE_CREDENTIAL) return;
        if (resultCode != RESULT_OK || pendingToolId == null || pendingVersion == null) {
            pendingToolId = null;
            pendingVersion = null;
            feedback.setText("Aprovação cancelada. Nenhuma decisão foi gravada.");
            return;
        }

        final String toolId = pendingToolId;
        final String version = pendingVersion;
        pendingToolId = null;
        pendingVersion = null;
        final long authenticatedAt = System.currentTimeMillis();
        feedback.setText("Registrando decisão…");
        io.execute(() -> {
            try {
                // Revalidate the candidate after authentication; a changed or
                // corrupted candidate/evidence cannot reuse this user action.
                approvals.recordDeviceCredentialApproval(
                    toolId, version, authenticatedAt);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Aprovação registrada. A versão permanece não ativa.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "A decisão não foi registrada: " + error.getMessage());
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
        button.setGravity(Gravity.CENTER);
        return button;
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT,
            android.graphics.Typeface.BOLD);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
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
