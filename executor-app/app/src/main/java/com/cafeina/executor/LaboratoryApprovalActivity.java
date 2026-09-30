package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.content.Context;
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

import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private UI for explicit human approval of STABLE activation/rollback.
 *
 * Authentication records a one-use receipt only. Applying the receipt is a
 * second explicit action. This Activity never runs a tool.
 */
public final class LaboratoryApprovalActivity extends Activity {
    private static final int REQUEST_DEVICE_CREDENTIAL = 5317;
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
    private String pendingAction;
    private String pendingToolId;
    private String pendingVersion;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        if (state != null) {
            pendingAction = state.getString("pending_action");
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
            "A CAFEÍNA não pode decidir isto por você. A autorização fica presa "
                + "à versão, artefato, snapshot e evidências exibidos. Confirmar "
                + "a identidade cria apenas um recibo; aplicar a mudança exige "
                + "uma segunda ação explícita.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando transições…", 14, MUTED, false);
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
            feedback.setText("Não foi possível abrir aprovações: " + error.getMessage());
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putString("pending_action", pendingAction);
        outState.putString("pending_tool_id", pendingToolId);
        outState.putString("pending_version", pendingVersion);
        super.onSaveInstanceState(outState);
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryToolRegistry.Descriptor> descriptors =
                    registry.listRegisteredVersions();
                List<LaboratoryHumanApprovalStore.Approval> receipts =
                    approvals.list();
                List<Option> options = new ArrayList<>();

                for (LaboratoryToolRegistry.Descriptor descriptor : descriptors) {
                    LaboratoryToolRegistry.Stage stage =
                        registry.stage(descriptor.toolId, descriptor.version);
                    if (stage == LaboratoryToolRegistry.Stage.CANDIDATE) {
                        try {
                            options.add(new Option(
                                approvals.previewActivation(
                                    descriptor.toolId, descriptor.version),
                                null));
                        } catch (Exception blocked) {
                            options.add(new Option(null,
                                descriptor.toolId + " @ " + descriptor.version
                                    + " • promoção bloqueada: " + blocked.getMessage()));
                        }
                    }
                }

                for (LaboratoryToolRegistry.Descriptor descriptor : descriptors) {
                    if (registry.stage(descriptor.toolId, descriptor.version)
                            != LaboratoryToolRegistry.Stage.STABLE) {
                        continue;
                    }
                    LaboratoryToolRegistry.Descriptor active =
                        registry.activeStable(descriptor.toolId);
                    if (active == null || active.version.equals(descriptor.version)) {
                        continue;
                    }
                    try {
                        options.add(new Option(
                            approvals.previewRollback(
                                descriptor.toolId, descriptor.version),
                            null));
                    } catch (Exception blocked) {
                        options.add(new Option(null,
                            descriptor.toolId + " @ " + descriptor.version
                                + " • rollback bloqueado: " + blocked.getMessage()));
                    }
                }

                runOnUiThread(() -> render(options, receipts));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao validar aprovações: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<Option> options,
            List<LaboratoryHumanApprovalStore.Approval> receipts) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(options.size() + " transição(ões) revisável(is) • "
            + receipts.size() + " recibo(s)");

        TextView decisions = text("DECISÕES DISPONÍVEIS", 17, FG, true);
        decisions.setPadding(0, dp(8), 0, dp(4));
        entries.addView(decisions, matchWrap());

        if (options.isEmpty()) {
            entries.addView(text(
                "Nenhuma promoção ou rollback aguarda decisão humana.",
                14, MUTED, false), matchWrap());
        }

        for (Option option : options) {
            if (option.preview == null) {
                TextView blocked = text(option.problem, 13, MUTED, false);
                blocked.setPadding(dp(12), dp(10), dp(12), dp(10));
                entries.addView(blocked, cardParams());
                continue;
            }
            LaboratoryHumanApprovalStore.Preview preview = option.preview;
            LinearLayout card = card();

            String actionLabel = LaboratoryHumanApprovalStore.ACTIVATE_STABLE
                .equals(preview.action) ? "PROMOVER PARA STABLE" : "ROLLBACK STABLE";
            String from = preview.fromVersion.isEmpty()
                ? "nenhuma STABLE ativa" : preview.fromVersion;
            TextView info = text(
                actionLabel
                    + "\n" + preview.toolId + " • " + from + " → " + preview.toVersion
                    + "\nArtefato SHA-256: " + preview.artifactSha256
                    + "\nSnapshot: " + preview.snapshotId
                    + "\nEvidências: " + preview.evidenceRunIds.size()
                    + " • Regressões: " + preview.regressionComparisonIds.size(),
                13, FG, true);
            info.setTextIsSelectable(true);
            card.addView(info, matchWrap());

            Button review = button("REVISAR E AUTORIZAR");
            review.setOnClickListener(v -> confirmApproval(preview));
            LinearLayout.LayoutParams buttonParams = matchWrap();
            buttonParams.setMargins(0, dp(8), 0, 0);
            card.addView(review, buttonParams);
            entries.addView(card, cardParams());
        }

        TextView receiptsTitle = text("RECIBOS DE AUTORIZAÇÃO", 17, FG, true);
        receiptsTitle.setPadding(0, dp(18), 0, dp(4));
        entries.addView(receiptsTitle, matchWrap());

        if (receipts.isEmpty()) {
            entries.addView(text(
                "Nenhuma autorização humana foi registrada neste projeto.",
                14, MUTED, false), matchWrap());
        }

        for (LaboratoryHumanApprovalStore.Approval approval : receipts) {
            LinearLayout card = card();
            String status = approval.consumed
                ? "APLICADA/CONSUMIDA" : "AUTORIZADA • AINDA NÃO APLICADA";
            TextView info = text(
                approval.toolId + " • " + approval.fromVersion + " → "
                    + approval.toVersion
                    + "\n" + status
                    + "\nAção: " + approval.action
                    + "\nAutorizada: " + time(approval.approvedAtEpochMs)
                    + "\nRecibo: " + approval.receiptId
                    + "\nArtefato SHA-256: " + approval.artifactSha256,
                13, approval.consumed ? MUTED : FG, true);
            info.setTextIsSelectable(true);
            card.addView(info, matchWrap());

            if (!approval.consumed) {
                Button apply = button(
                    LaboratoryHumanApprovalStore.ACTIVATE_STABLE.equals(approval.action)
                        ? "APLICAR PROMOÇÃO STABLE" : "APLICAR ROLLBACK");
                apply.setOnClickListener(v -> confirmApply(approval));
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(8), 0, 0);
                card.addView(apply, params);
            }
            entries.addView(card, cardParams());
        }
    }

    private void confirmApproval(LaboratoryHumanApprovalStore.Preview preview) {
        String action = LaboratoryHumanApprovalStore.ACTIVATE_STABLE.equals(preview.action)
            ? "promover esta versão para STABLE"
            : "autorizar rollback para esta versão";
        String from = preview.fromVersion.isEmpty() ? "nenhuma" : preview.fromVersion;
        String message = "Ferramenta: " + preview.toolId
            + "\nTransição: " + from + " → " + preview.toVersion
            + "\nArtefato SHA-256: " + preview.artifactSha256
            + "\nDescriptor SHA-256: " + preview.descriptorSha256
            + "\nSnapshot: " + preview.snapshotId
            + "\nRelatórios de teste: " + preview.evidenceRunIds.size()
            + "\nComparações de regressão: " + preview.regressionComparisonIds.size()
            + "\n\nSua credencial do Android autorizará somente esta transição. "
            + "Ela ainda não será aplicada automaticamente.";

        new AlertDialog.Builder(this)
            .setTitle("Confirmar decisão humana")
            .setMessage(message)
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CONFIRMAR IDENTIDADE", (dialog, which) ->
                requestCredential(preview, action))
            .show();
    }

    private void requestCredential(LaboratoryHumanApprovalStore.Preview preview,
            String actionDescription) {
        KeyguardManager keyguard =
            (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (keyguard == null || !keyguard.isDeviceSecure()) {
            new AlertDialog.Builder(this)
                .setTitle("Bloqueio seguro necessário")
                .setMessage("Configure PIN, senha ou outro bloqueio seguro do Android "
                    + "antes de autorizar mudanças STABLE.")
                .setPositiveButton("OK", null)
                .show();
            return;
        }
        Intent credential = keyguard.createConfirmDeviceCredentialIntent(
            "CAFEÍNA • autorização humana",
            "Confirme sua identidade para " + actionDescription + ".");
        if (credential == null) {
            feedback.setText("O Android não disponibilizou a confirmação de identidade.");
            return;
        }
        pendingAction = preview.action;
        pendingToolId = preview.toolId;
        pendingVersion = preview.toVersion;
        startActivityForResult(credential, REQUEST_DEVICE_CREDENTIAL);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_DEVICE_CREDENTIAL) return;

        if (resultCode != RESULT_OK || pendingAction == null
                || pendingToolId == null || pendingVersion == null) {
            clearPending();
            feedback.setText("Autorização cancelada. Nenhum recibo foi criado.");
            return;
        }

        final String action = pendingAction;
        final String toolId = pendingToolId;
        final String version = pendingVersion;
        final long authenticatedAt = System.currentTimeMillis();
        clearPending();
        feedback.setText("Registrando autorização…");

        io.execute(() -> {
            try {
                approvals.recordDeviceCredentialApproval(
                    action, toolId, version, authenticatedAt);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText(
                        "Autorização registrada. A mudança ainda não foi aplicada.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "A autorização não foi registrada: " + error.getMessage());
                });
            }
        });
    }

    private void confirmApply(LaboratoryHumanApprovalStore.Approval approval) {
        String label = LaboratoryHumanApprovalStore.ACTIVATE_STABLE.equals(approval.action)
            ? "ATIVAR STABLE" : "EXECUTAR ROLLBACK";
        new AlertDialog.Builder(this)
            .setTitle(label)
            .setMessage("Aplicar agora a transição "
                + (approval.fromVersion.isEmpty() ? "nenhuma" : approval.fromVersion)
                + " → " + approval.toVersion + "?\n\n"
                + "O recibo será consumido e não poderá ser reutilizado.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton(label, (dialog, which) -> apply(approval.receiptId))
            .show();
    }

    private void apply(String receiptId) {
        feedback.setText("Aplicando decisão aprovada…");
        io.execute(() -> {
            try {
                approvals.applyApprovedTransition(receiptId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Mudança STABLE aplicada e auditada.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "A mudança não foi aplicada: " + error.getMessage());
                });
            }
        });
    }

    private void clearPending() {
        pendingAction = null;
        pendingToolId = null;
        pendingVersion = null;
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackgroundTintList(ColorStateList.valueOf(PANEL));
        return card;
    }

    private LinearLayout.LayoutParams cardParams() {
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, dp(8), 0, 0);
        return params;
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

    private static String time(long epochMs) {
        return DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT,
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

    private static final class Option {
        final LaboratoryHumanApprovalStore.Preview preview;
        final String problem;

        Option(LaboratoryHumanApprovalStore.Preview preview, String problem) {
            this.preview = preview;
            this.problem = problem;
        }
    }
}
