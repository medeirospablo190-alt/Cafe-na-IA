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

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Human control plane for selecting which already-approved tool version may be
 * considered STABLE for future AI use. No tool execution occurs in this screen.
 */
public final class LaboratoryStableToolsActivity extends Activity {
    private static final int REQUEST_CREDENTIAL = 4111;
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
    private LaboratoryStableActivationStore stable;
    private String pendingAction;
    private String pendingToolId;
    private String pendingVersion;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        if (state != null) {
            pendingAction = state.getString("stable_pending_action");
            pendingToolId = state.getString("stable_pending_tool");
            pendingVersion = state.getString("stable_pending_version");
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR AOS RELATÓRIOS");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("FERRAMENTAS STABLE • CONTROLE HUMANO", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());
        root.addView(text(
            "Somente versões já testadas e aprovadas por você aparecem aqui. "
                + "Ativar marca qual versão uma futura IA poderá usar; não executa "
                + "a ferramenta agora. Toda troca ou desativação exige sua credencial Android.",
            14, MUTED, false), matchWrap());

        feedback = text("Validando ferramentas e aprovações…", 14, MUTED, false);
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
            stable = new LaboratoryStableActivationStore(getFilesDir(), projectId);
            refresh();
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir o controle STABLE: "
                + error.getMessage());
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putString("stable_pending_action", pendingAction);
        state.putString("stable_pending_tool", pendingToolId);
        state.putString("stable_pending_version", pendingVersion);
        super.onSaveInstanceState(state);
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryToolRegistry.Tool> tools = registry.list();
                runOnUiThread(() -> render(tools));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao validar ferramentas STABLE: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryToolRegistry.Tool> tools) {
        if (!alive()) return;
        entries.removeAllViews();
        int eligible = 0;
        for (LaboratoryToolRegistry.Tool tool : tools) {
            if (tool.state != LaboratoryToolRegistry.State.CANDIDATE) continue;
            final boolean approved;
            final LaboratoryStableActivationStore.Active active;
            try {
                approved = approvals.isApproved(tool.id, tool.version);
                active = stable.current(tool.id);
            } catch (Exception error) {
                TextView warning = text(tool.id + " @ " + tool.version
                    + "\nEVIDÊNCIA STABLE INCONSISTENTE: " + error.getMessage(),
                    13, FG, true);
                warning.setPadding(dp(12), dp(10), dp(12), dp(10));
                entries.addView(warning, matchWrap());
                continue;
            }
            if (!approved) continue;
            eligible++;

            boolean thisActive = active != null && active.version.equals(tool.version);
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            String state = thisActive
                ? "STABLE • ATIVA PARA FUTURA IA"
                : active == null ? "APROVADA • NÃO ATIVA"
                : "APROVADA • outra versão está ativa: " + active.version;
            TextView info = text(tool.id + " @ " + tool.version + "\n" + state
                + "\nManifesto: " + tool.manifestSha256
                + "\nFonte: " + tool.sourceSha256
                + "\nEvidência: " + tool.evidenceRunId,
                13, thisActive ? FG : MUTED, true);
            info.setTextIsSelectable(true);
            card.addView(info, matchWrap());

            Button action = button(thisActive ? "DESATIVAR STABLE"
                : active == null ? "ATIVAR COMO STABLE"
                : "TROCAR / REVERTER PARA ESTA VERSÃO");
            action.setOnClickListener(v -> {
                if (thisActive) confirmDeactivate(tool);
                else confirmActivate(tool, active);
            });
            LinearLayout.LayoutParams buttonParams = matchWrap();
            buttonParams.setMargins(0, dp(8), 0, 0);
            card.addView(action, buttonParams);

            LinearLayout.LayoutParams cardParams = matchWrap();
            cardParams.setMargins(0, dp(8), 0, 0);
            entries.addView(card, cardParams);
        }

        feedback.setText(eligible + " versão(ões) aprovada(s) elegível(is)");
        if (eligible == 0) {
            entries.addView(text(
                "Nenhuma versão aprovada está pronta para ativação neste projeto. "
                    + "Primeiro a candidata precisa passar nos testes e receber sua aprovação.",
                14, MUTED, false), matchWrap());
        }
    }

    private void confirmActivate(LaboratoryToolRegistry.Tool tool,
            LaboratoryStableActivationStore.Active current) {
        String switchText = current == null
            ? "Nenhuma versão está ativa agora."
            : "A versão " + current.version
                + " deixará de ser a seleção ativa. O histórico será preservado.";
        new AlertDialog.Builder(this)
            .setTitle("Ativar versão STABLE")
            .setMessage("Ferramenta: " + tool.id + "\nVersão: " + tool.version
                + "\n\n" + switchText
                + "\n\nIsto não executará a ferramenta. A seleção apenas ficará "
                + "disponível para o futuro controlador da IA.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CONFIRMAR IDENTIDADE", (dialog, which) ->
                requestCredential("ACTIVATE", tool.id, tool.version))
            .show();
    }

    private void confirmDeactivate(LaboratoryToolRegistry.Tool tool) {
        new AlertDialog.Builder(this)
            .setTitle("Desativar ferramenta STABLE")
            .setMessage("Ferramenta: " + tool.id + "\nVersão ativa: " + tool.version
                + "\n\nA futura IA deixará de ter uma versão ativa desta ferramenta. "
                + "Nenhum histórico, snapshot ou relatório será apagado.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CONFIRMAR IDENTIDADE", (dialog, which) ->
                requestCredential("DEACTIVATE", tool.id, tool.version))
            .show();
    }

    private void requestCredential(String action, String toolId, String version) {
        KeyguardManager keyguard =
            (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (keyguard == null || !keyguard.isDeviceSecure()) {
            new AlertDialog.Builder(this)
                .setTitle("Bloqueio de tela necessário")
                .setMessage("Configure PIN, senha ou outro bloqueio seguro do Android "
                    + "antes de alterar uma seleção STABLE.")
                .setPositiveButton("OK", null)
                .show();
            return;
        }
        Intent credential = keyguard.createConfirmDeviceCredentialIntent(
            "Alterar ferramenta STABLE da CAFEÍNA",
            "Confirme o bloqueio do aparelho para registrar esta mudança.");
        if (credential == null) {
            feedback.setText("O Android não disponibilizou a confirmação de identidade.");
            return;
        }
        pendingAction = action;
        pendingToolId = toolId;
        pendingVersion = version;
        startActivityForResult(credential, REQUEST_CREDENTIAL);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_CREDENTIAL) return;
        if (resultCode != RESULT_OK || pendingAction == null || pendingToolId == null) {
            clearPending();
            feedback.setText("Alteração STABLE cancelada. Nada foi gravado.");
            return;
        }

        final String action = pendingAction;
        final String toolId = pendingToolId;
        final String version = pendingVersion;
        clearPending();
        final long authenticatedAt = System.currentTimeMillis();
        feedback.setText("Registrando mudança STABLE…");
        io.execute(() -> {
            try {
                if ("ACTIVATE".equals(action)) {
                    stable.activateApproved(toolId, version, authenticatedAt);
                } else if ("DEACTIVATE".equals(action)) {
                    stable.deactivate(toolId, authenticatedAt);
                } else {
                    throw new IllegalStateException("unknown STABLE action");
                }
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Mudança registrada. Nenhuma ferramenta foi executada.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "A mudança STABLE não foi registrada: " + error.getMessage());
                });
            }
        });
    }

    private void clearPending() {
        pendingAction = null;
        pendingToolId = null;
        pendingVersion = null;
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
