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
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private user-only UI controlling which active STABLE tools may be exposed to
 * the future AI controller. It never executes a tool.
 */
public final class LaboratoryAiPermissionsActivity extends Activity {
    private static final int REQUEST_DEVICE_CREDENTIAL = 6419;
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);
    private static final int ACCENT = Color.rgb(59, 139, 254);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView feedback;
    private LinearLayout entries;
    private LaboratoryToolRegistry registry;
    private LaboratoryAiPermissionStore permissions;
    private String projectId;
    private String pendingToolId;
    private volatile boolean bootstrapBusy;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        if (state != null) pendingToolId = state.getString("pending_tool_id");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(14), dp(16), dp(14));
        root.setBackgroundColor(BG);
        setContentView(root);

        Button back = button("← VOLTAR");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("PERMISSÕES DA IA • FERRAMENTAS", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());
        root.addView(text(
            "Padrão: BLOQUEADO. Tornar uma ferramenta STABLE não libera seu uso "
                + "pela IA. Cada versão precisa de uma autorização separada; uma "
                + "promoção ou rollback invalida automaticamente a autorização anterior.",
            14, MUTED, false), matchWrap());

        feedback = text("Carregando ferramentas STABLE…", 14, MUTED, false);
        feedback.setPadding(0, dp(12), 0, dp(8));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        projectId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        try {
            registry = new LaboratoryToolRegistry(getFilesDir(), projectId);
            permissions = new LaboratoryAiPermissionStore(getFilesDir(), projectId);
        } catch (Exception error) {
            feedback.setText("Não foi possível abrir permissões: " + error.getMessage());
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (registry != null && permissions != null && !bootstrapBusy) {
            refresh();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        outState.putString("pending_tool_id", pendingToolId);
        super.onSaveInstanceState(outState);
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<LaboratoryToolRegistry.Descriptor> all =
                    registry.listRegisteredVersions();
                List<LaboratoryToolRegistry.Descriptor> active = new ArrayList<>();
                Set<String> seen = new HashSet<>();
                for (LaboratoryToolRegistry.Descriptor descriptor : all) {
                    if (seen.contains(descriptor.toolId)) continue;
                    LaboratoryToolRegistry.Descriptor stable =
                        registry.activeStable(descriptor.toolId);
                    if (stable == null) continue;
                    seen.add(descriptor.toolId);
                    active.add(stable);
                }
                LaboratoryInitialDiagnosticTool.State bootstrapState =
                    LaboratoryInitialDiagnosticTool.state(
                        getFilesDir(), projectId);
                runOnUiThread(() -> render(active, bootstrapState));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha ao validar permissões: " + error.getMessage());
                });
            }
        });
    }

    private void render(
            List<LaboratoryToolRegistry.Descriptor> active,
            LaboratoryInitialDiagnosticTool.State bootstrapState) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(active.size() + " ferramenta(s) STABLE ativa(s)");

        if (active.isEmpty()) {
            LinearLayout onboarding = new LinearLayout(this);
            onboarding.setOrientation(LinearLayout.VERTICAL);
            onboarding.setPadding(dp(12), dp(10), dp(12), dp(10));
            onboarding.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            if (bootstrapState == LaboratoryInitialDiagnosticTool.State.MISSING
                    || bootstrapState
                        == LaboratoryInitialDiagnosticTool.State.EXPERIMENTAL) {
                onboarding.addView(text(
                    "Este projeto ainda não possui uma ferramenta STABLE. "
                        + "Prepare o diagnóstico inicial para criar, verificar "
                        + "e congelar uma ferramenta mínima como CANDIDATE. "
                        + "Ela ainda NÃO será STABLE e NÃO será liberada para a IA.",
                    14, MUTED, false), matchWrap());

                Button prepare = button(
                    bootstrapBusy
                        ? "PREPARANDO DIAGNÓSTICO…"
                        : "PREPARAR DIAGNÓSTICO INICIAL");
                prepare.setEnabled(!bootstrapBusy);
                prepare.setOnClickListener(v ->
                    prepareInitialDiagnostic());
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(10), 0, 0);
                onboarding.addView(prepare, params);
            } else if (bootstrapState
                    == LaboratoryInitialDiagnosticTool.State.CANDIDATE) {
                onboarding.addView(text(
                    "diagnostic-roundtrip @ 1.0.0 está CANDIDATE. "
                        + "O artefato já foi verificado, mas somente você pode "
                        + "autorizar a promoção para STABLE.",
                    14, FG, true), matchWrap());

                Button approve = button(
                    "REVISAR PROMOÇÃO PARA STABLE");
                approve.setOnClickListener(v ->
                    startActivity(new Intent(
                        this, LaboratoryApprovalActivity.class)));
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(10), 0, 0);
                onboarding.addView(approve, params);
            } else {
                onboarding.addView(text(
                    "A ferramenta inicial já passou por STABLE, mas não foi "
                        + "possível resolver uma seleção STABLE ativa. "
                        + "Revise APROVAÇÕES HUMANAS antes de continuar.",
                    14, MUTED, false), matchWrap());

                Button approvals = button(
                    "ABRIR APROVAÇÕES HUMANAS");
                approvals.setOnClickListener(v ->
                    startActivity(new Intent(
                        this, LaboratoryApprovalActivity.class)));
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(10), 0, 0);
                onboarding.addView(approvals, params);
            }

            entries.addView(onboarding, matchWrap());
            return;
        }

        for (LaboratoryToolRegistry.Descriptor descriptor : active) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundTintList(ColorStateList.valueOf(PANEL));

            final boolean eligible = descriptor.capabilities.contains(
                LaboratoryStableToolExecutor.REQUIRED_CAPABILITY);
            boolean granted = false;
            String problem = null;
            if (eligible) {
                try {
                    granted = permissions.isGranted(descriptor.toolId);
                } catch (Exception error) {
                    problem = error.getMessage();
                }
            }

            String status = !eligible
                ? "NÃO ELEGÍVEL PARA EXECUÇÃO ISOLADA"
                : problem != null
                    ? "PERMISSÃO INDISPONÍVEL"
                    : granted ? "LIBERADA PARA IA" : "BLOQUEADA PARA IA";

            TextView info = text(
                descriptor.toolId + " @ " + descriptor.version
                    + "\n" + status
                    + "\nArtefato SHA-256: " + descriptor.artifactSha256
                    + "\nLimite: " + descriptor.maxRuntimeMs + " ms • "
                    + descriptor.maxInputBytes + " bytes"
                    + (problem == null ? "" : "\nErro: " + problem),
                13, granted ? FG : MUTED, true);
            info.setTextIsSelectable(true);
            card.addView(info, matchWrap());

            if (eligible && problem == null) {
                if (!granted) {
                    Button grant = button("LIBERAR ESTA STABLE PARA A IA");
                    grant.setOnClickListener(v -> confirmGrant(descriptor));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    card.addView(grant, params);
                } else {
                    Button revoke = button("REVOGAR ACESSO DA IA");
                    revoke.setOnClickListener(v -> confirmRevoke(descriptor.toolId));
                    LinearLayout.LayoutParams params = matchWrap();
                    params.setMargins(0, dp(8), 0, 0);
                    card.addView(revoke, params);
                }
            }

            LinearLayout.LayoutParams params = matchWrap();
            params.setMargins(0, dp(8), 0, 0);
            entries.addView(card, params);
        }
    }

    private void prepareInitialDiagnostic() {
        if (bootstrapBusy) return;
        bootstrapBusy = true;
        feedback.setText(
            "Criando snapshot, verificando artefato e preparando CANDIDATE…");
        entries.removeAllViews();

        io.execute(() -> {
            try {
                LaboratoryInitialDiagnosticTool.State state =
                    LaboratoryInitialDiagnosticTool.prepareCandidate(
                        this, projectId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    bootstrapBusy = false;
                    feedback.setText(
                        state
                            == LaboratoryInitialDiagnosticTool.State.CANDIDATE
                            ? "Diagnóstico inicial verificado • CANDIDATE pronto para sua aprovação"
                            : "Diagnóstico inicial já estava " + state.name());
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    bootstrapBusy = false;
                    feedback.setText(
                        "Diagnóstico inicial não foi preparado: "
                            + String.valueOf(error.getMessage()));
                    refresh();
                });
            }
        });
    }

    private void confirmGrant(LaboratoryToolRegistry.Descriptor descriptor) {
        new AlertDialog.Builder(this)
            .setTitle("Liberar ferramenta para a IA")
            .setMessage("Ferramenta: " + descriptor.toolId
                + "\nVersão STABLE: " + descriptor.version
                + "\nArtefato SHA-256: " + descriptor.artifactSha256
                + "\n\nEsta autorização permite que a futura IA execute somente "
                + "esta STABLE pelo worker isolado, com tool_input limitado. "
                + "Ela não recebe acesso às aprovações, versões ou snapshots.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("CONFIRMAR IDENTIDADE", (dialog, which) ->
                requestCredential(descriptor.toolId))
            .show();
    }

    private void requestCredential(String toolId) {
        KeyguardManager keyguard =
            (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (keyguard == null || !keyguard.isDeviceSecure()) {
            new AlertDialog.Builder(this)
                .setTitle("Bloqueio seguro necessário")
                .setMessage("Configure PIN, senha ou outro bloqueio seguro do Android "
                    + "antes de liberar uma ferramenta para a IA.")
                .setPositiveButton("OK", null)
                .show();
            return;
        }
        Intent credential = keyguard.createConfirmDeviceCredentialIntent(
            "CAFEÍNA • permissão da IA",
            "Confirme sua identidade para liberar esta ferramenta STABLE à IA.");
        if (credential == null) {
            feedback.setText("O Android não disponibilizou a confirmação de identidade.");
            return;
        }
        pendingToolId = toolId;
        startActivityForResult(credential, REQUEST_DEVICE_CREDENTIAL);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_DEVICE_CREDENTIAL) return;
        if (resultCode != RESULT_OK || pendingToolId == null) {
            pendingToolId = null;
            feedback.setText("Permissão cancelada. A IA continua bloqueada.");
            return;
        }

        final String toolId = pendingToolId;
        final long authenticatedAt = System.currentTimeMillis();
        pendingToolId = null;
        feedback.setText("Registrando permissão…");

        io.execute(() -> {
            try {
                permissions.grantAfterDeviceCredential(toolId, authenticatedAt);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Ferramenta liberada para a IA nesta STABLE.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Permissão não registrada: " + error.getMessage());
                });
            }
        });
    }

    private void confirmRevoke(String toolId) {
        new AlertDialog.Builder(this)
            .setTitle("Revogar acesso da IA")
            .setMessage("Bloquear imediatamente novas execuções de " + toolId
                + "? Uma execução já iniciada terá o resultado descartado "
                + "se a revogação ocorrer antes de ela terminar.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("REVOGAR", (dialog, which) -> revoke(toolId))
            .show();
    }

    private void revoke(String toolId) {
        feedback.setText("Revogando acesso…");
        io.execute(() -> {
            try {
                permissions.revoke(toolId);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Acesso da IA revogado.");
                    refresh();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Não foi possível revogar: " + error.getMessage());
                });
            }
        });
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextSize(14);
        button.setTextColor(FG);
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
