package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.text.DateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Private user-only recovery UI. It never resumes AI work automatically.
 */
public final class LaboratoryAiSessionRecoveryActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(170, 177, 192);
    private static final int PANEL = Color.rgb(36, 41, 52);

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private TextView feedback;
    private LinearLayout entries;
    private LaboratoryAiSessionRecovery recovery;

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

        Button back = button("← VOLTAR", Color.rgb(59, 139, 254));
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("RECUPERAÇÃO • SESSÕES DA IA", 20, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());

        root.addView(text(
            "Sessões encontradas ACTIVE/PAUSED após a perda do processo são "
                + "interrompidas por segurança. Nada volta a executar sozinho. "
                + "Você decide se quer encerrar ou preparar uma nova sessão "
                + "usando apenas o orçamento que ainda restava.",
            14, MUTED, false), matchWrap());

        feedback = text("Verificando sessões…", 14, MUTED, false);
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
        recovery = new LaboratoryAiSessionRecovery(getFilesDir(), projectId);
        refresh(true);
    }

    private void refresh(boolean markOrphans) {
        io.execute(() -> {
            try {
                List<LaboratoryAiSessionRecovery.Item> items =
                    markOrphans ? recovery.markInterruptedOrphans()
                        : recovery.listActionable();
                runOnUiThread(() -> render(items));
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText(
                        "Falha na recuperação: " + error.getMessage());
                });
            }
        });
    }

    private void render(List<LaboratoryAiSessionRecovery.Item> items) {
        if (!alive()) return;
        entries.removeAllViews();
        feedback.setText(items.size() + " sessão(ões) aguardando decisão");

        if (items.isEmpty()) {
            entries.addView(text(
                "Nenhuma sessão interrompida aguarda recuperação.",
                14, MUTED, false), matchWrap());
            return;
        }

        for (LaboratoryAiSessionRecovery.Item item : items) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundColor(PANEL);

            String status = "INTERRUPTED".equals(item.state)
                ? "INTERROMPIDA • decisão necessária"
                : "RETOMADA PREPARADA • ainda não executando";
            TextView details = text(
                status
                    + "\nSessão: " + item.sessionId
                    + "\nInício: " + time(item.startedAtEpochMs)
                    + "\nÚltimo evento: " + time(item.lastEventAtEpochMs)
                    + "\nFerramentas: " + item.allowedToolIds
                    + "\nChamadas restantes: " + item.invocationsRemaining
                    + "\nEntrada restante: " + item.inputBytesRemaining + " bytes"
                    + "\nTempo restante calculado: "
                    + item.remainingSessionMs + " ms",
                13, FG, true);
            details.setTextIsSelectable(true);
            card.addView(details, matchWrap());

            if ("INTERRUPTED".equals(item.state) && item.canRequestRestart()) {
                Button prepare = button(
                    "PREPARAR RETOMADA EM NOVA SESSÃO",
                    Color.rgb(48, 121, 89));
                prepare.setOnClickListener(v -> confirmPrepare(item));
                LinearLayout.LayoutParams params = matchWrap();
                params.setMargins(0, dp(8), 0, 0);
                card.addView(prepare, params);
            }

            Button close = button("ENCERRAR ESTA SESSÃO", Color.rgb(121, 61, 61));
            close.setOnClickListener(v -> confirmClose(item));
            LinearLayout.LayoutParams closeParams = matchWrap();
            closeParams.setMargins(0, dp(8), 0, 0);
            card.addView(close, closeParams);

            LinearLayout.LayoutParams params = matchWrap();
            params.setMargins(0, dp(8), 0, 0);
            entries.addView(card, params);
        }
    }

    private void confirmPrepare(LaboratoryAiSessionRecovery.Item item) {
        new AlertDialog.Builder(this)
            .setTitle("Preparar retomada")
            .setMessage("Registrar sua decisão de continuar este trabalho em uma "
                + "NOVA sessão usando apenas o orçamento restante?\n\n"
                + "Nenhuma IA ou ferramenta será executada agora.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("PREPARAR", (dialog, which) -> {
                feedback.setText("Registrando decisão de retomada…");
                io.execute(() -> {
                    try {
                        recovery.requestRestart(item.sessionId);
                        runOnUiThread(() -> {
                            if (!alive()) return;
                            feedback.setText(
                                "Retomada preparada. Nada foi executado automaticamente.");
                            refresh(false);
                        });
                    } catch (Exception error) {
                        runOnUiThread(() -> {
                            if (alive()) feedback.setText(
                                "Não foi possível preparar retomada: "
                                    + error.getMessage());
                        });
                    }
                });
            })
            .show();
    }

    private void confirmClose(LaboratoryAiSessionRecovery.Item item) {
        new AlertDialog.Builder(this)
            .setTitle("Encerrar sessão interrompida")
            .setMessage("Encerrar definitivamente esta sessão antiga? "
                + "O histórico continuará preservado.")
            .setNegativeButton("CANCELAR", null)
            .setPositiveButton("ENCERRAR", (dialog, which) -> {
                feedback.setText("Encerrando sessão…");
                io.execute(() -> {
                    try {
                        recovery.close(item.sessionId);
                        runOnUiThread(() -> {
                            if (!alive()) return;
                            feedback.setText("Sessão antiga encerrada.");
                            refresh(false);
                        });
                    } catch (Exception error) {
                        runOnUiThread(() -> {
                            if (alive()) feedback.setText(
                                "Não foi possível encerrar: " + error.getMessage());
                        });
                    }
                });
            })
            .show();
    }

    private Button button(String label, int color) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(FG);
        button.setTextSize(14);
        button.setBackgroundTintList(
            android.content.res.ColorStateList.valueOf(color));
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
