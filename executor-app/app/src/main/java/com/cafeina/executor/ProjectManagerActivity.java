package com.cafeina.executor;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native, offline project management. The legacy editor is intentionally not migrated here. */
public final class ProjectManagerActivity extends Activity {
    private static final int BG = Color.rgb(12, 13, 16);
    private static final int FG = Color.rgb(240, 242, 247);
    private static final int MUTED = Color.rgb(180, 185, 196);
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private ProjectStore projects;
    private EditText projectId;
    private TextView feedback;
    private LinearLayout entries;
    private Button createButton;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        projects = new ProjectStore(getFilesDir());
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setPadding(dp(18), dp(14), dp(18), dp(14));
        setContentView(root);

        Button back = button("← CÓDIGO");
        back.setOnClickListener(v -> finish());
        root.addView(back, matchWrap());

        TextView title = text("SISTEMA • PROJETOS", 22, FG, true);
        title.setPadding(0, dp(16), 0, dp(6));
        root.addView(title, matchWrap());
        root.addView(text(
            "Escolha um projeto para abrir no editor. Cada projeto guarda scripts e arquivos Luau separados. Seus scripts antigos continuam disponíveis.",
            15, MUTED, false), matchWrap());

        String currentId = getSharedPreferences("cafeina_workspace", MODE_PRIVATE)
            .getString("project_id", "");
        TextView current = text(
            "Área atual: " + (currentId.isEmpty() ? "Scripts antigos" : currentId),
            16, FG, true);
        current.setPadding(0, dp(14), 0, dp(8));
        root.addView(current, matchWrap());

        // The laboratory is AI-operated. The user can only inspect its reports.
        Button laboratoryReports = button("RELATÓRIOS DO LABORATÓRIO");
        laboratoryReports.setOnClickListener(v ->
            startActivity(new Intent(this, LaboratoryReportsActivity.class)));
        root.addView(laboratoryReports, matchWrap());

        Button legacy = button("ABRIR SCRIPTS ANTIGOS");
        legacy.setOnClickListener(v -> activateProject(""));
        root.addView(legacy, matchWrap());

        projectId = new EditText(this);
        projectId.setSingleLine(true);
        projectId.setTextSize(18);
        projectId.setTextColor(FG);
        projectId.setHintTextColor(MUTED);
        projectId.setHint("Nome curto: meu-jogo");
        projectId.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        LinearLayout.LayoutParams inputParams = matchWrap();
        inputParams.setMargins(0, dp(16), 0, dp(8));
        root.addView(projectId, inputParams);

        createButton = button("CRIAR E ABRIR PROJETO");
        createButton.setOnClickListener(v -> createProject());
        root.addView(createButton, matchWrap());

        feedback = text("Carregando projetos locais…", 14, MUTED, false);
        feedback.setPadding(0, dp(12), 0, dp(12));
        root.addView(feedback, matchWrap());

        ScrollView scroll = new ScrollView(this);
        entries = new LinearLayout(this);
        entries.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(entries);
        root.addView(scroll,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        refresh();
    }

    private void createProject() {
        String id = projectId.getText().toString().trim();
        if (!ProjectStore.isValidId(id)) {
            feedback.setText("Use letras minúsculas, números, - ou _. O nome deve começar com letra ou número e ter até 64 caracteres.");
            return;
        }
        createButton.setEnabled(false);
        feedback.setText("Criando " + id + "…");
        io.execute(() -> {
            try {
                projects.create(id);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    projectId.setText("");
                    feedback.setText("Projeto criado: " + id);
                    createButton.setEnabled(true);
                    activateProject(id);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (!alive()) return;
                    feedback.setText("Não foi possível criar o projeto: " + error.getMessage());
                    createButton.setEnabled(true);
                });
            }
        });
    }

    private void refresh() {
        io.execute(() -> {
            try {
                List<String> ids = projects.listProjectIds();
                runOnUiThread(() -> {
                    if (!alive()) return;
                    entries.removeAllViews();
                    if (ids.isEmpty()) {
                        entries.addView(text("Nenhum projeto criado ainda.", 15, MUTED, false),
                            matchWrap());
                        return;
                    }
                    for (String id : ids) {
                        Button item = button(id + "  •  ABRIR");
                        item.setOnClickListener(v -> showProject(id));
                        LinearLayout.LayoutParams params = matchWrap();
                        params.setMargins(0, 0, 0, dp(8));
                        entries.addView(item, params);
                    }
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText("Erro ao listar projetos: " + error.getMessage());
                });
            }
        });
    }

    private void showProject(String id) {
        io.execute(() -> {
            try {
                projects.open(id);
                runOnUiThread(() -> {
                    if (!alive()) return;
                    new AlertDialog.Builder(this)
                        .setTitle("Projeto: " + id)
                        .setMessage("Abrir este projeto no editor? Os arquivos do projeto ficam separados dos scripts antigos e dos outros projetos.")
                        .setPositiveButton("ABRIR", (dialog, which) -> activateProject(id))
                        .setNegativeButton("CANCELAR", null)
                        .show();
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (alive()) feedback.setText("Projeto indisponível: " + error.getMessage());
                });
            }
        });
    }


    private void activateProject(String id) {
        if (!getSharedPreferences("cafeina_workspace", MODE_PRIVATE).edit()
                .putString("project_id", id).commit()) {
            feedback.setText("Não foi possível guardar a escolha do projeto.");
            return;
        }
        Intent openEditor = new Intent(this, MainActivity.class);
        openEditor.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(openEditor);
        finish();
    }

    private TextView text(String value, int sp, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(sp);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private Button button(String value) {
        Button view = new Button(this);
        view.setText(value);
        view.setTextColor(FG);
        view.setTextSize(14);
        view.setAllCaps(false);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT);
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
