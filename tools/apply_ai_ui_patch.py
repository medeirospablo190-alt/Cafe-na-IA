from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def splice_once(text: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    require(start >= 0 and end >= 0, f"{label} anchors changed")
    require(text.find(start_marker, start + 1) < 0, f"{label} start anchor is not unique")
    return text[:start] + replacement + text[end:]


main_path = Path("executor-app/app/src/main/java/com/cafeina/executor/MainActivity.java")
main = main_path.read_text(encoding="utf-8")

import_marker = "import android.widget.TextView;\n"
if "import androidx.drawerlayout.widget.DrawerLayout;" not in main:
    require(main.count(import_marker) == 1, "MainActivity import anchor changed")
    main = main.replace(
        import_marker,
        import_marker + "\nimport androidx.drawerlayout.widget.DrawerLayout;\n",
        1,
    )

new_section = r'''    private void showSection(String name) {
        if ("MUNDO".equals(name)) {
            openWorld();
            return;
        }
        if ("SISTEMA".equals(name)) {
            openProjectManager();
            return;
        }
        for (Map.Entry<String, Button> item : navigation.entrySet()) {
            item.getValue().setBackgroundTintList(ColorStateList.valueOf(
                item.getKey().equals(name) ? ACCENT : PANEL_2
            ));
        }
        screenHost.removeAllViews();
        if ("CÓDIGO".equals(name)) {
            screenHost.addView(codeScreen,
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));
            return;
        }
        if ("IA".equals(name)) {
            showAiSection();
            return;
        }

        LinearLayout section = new LinearLayout(this);
        section.setOrientation(LinearLayout.VERTICAL);
        section.setPadding(dp(20), dp(30), dp(20), dp(20));
        TextView title = new TextView(this);
        title.setText(name);
        title.setTextSize(22);
        title.setTextColor(TEXT);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        section.addView(title, matchWrap());

        TextView detail = new TextView(this);
        detail.setTextSize(16);
        detail.setTextColor(MUTED);
        detail.setPadding(0, dp(15), 0, dp(22));
        if ("3D".equals(name)) {
            detail.setText("O módulo de criação e edição 3D ainda está em desenvolvimento. Nenhuma alteração será feita nos seus scripts ao entrar nesta área.");
        } else {
            detail.setText("A execução Luau, o editor e o armazenamento privado já estão disponíveis na aba CÓDIGO.");
        }
        section.addView(detail, matchWrap());

        Button back = makeButton("VOLTAR AO CÓDIGO", ACCENT);
        back.setOnClickListener(v -> showSection("CÓDIGO"));
        section.addView(back, matchWrap());
        screenHost.addView(section,
            new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private void showAiSection() {
        if (aiChatPanel == null) {
            aiChatPanel = new LaboratoryAiChatPanel(this, workspace.id());
        }

        DrawerLayout drawer = new DrawerLayout(this);
        drawer.setBackgroundColor(BG);

        LinearLayout chatSurface = new LinearLayout(this);
        chatSurface.setOrientation(LinearLayout.VERTICAL);
        chatSurface.setBackgroundColor(BG);
        chatSurface.setPadding(dp(10), dp(4), dp(10), dp(8));

        LinearLayout compactHeader = new LinearLayout(this);
        compactHeader.setOrientation(LinearLayout.HORIZONTAL);
        compactHeader.setGravity(Gravity.CENTER_VERTICAL);

        TextView menu = new TextView(this);
        menu.setText("☰");
        menu.setTextColor(TEXT);
        menu.setTextSize(24);
        menu.setGravity(Gravity.CENTER);
        menu.setContentDescription("Abrir opções da IA");
        menu.setOnClickListener(v -> drawer.openDrawer(Gravity.START));
        compactHeader.addView(menu,
            new LinearLayout.LayoutParams(dp(46), dp(42)));

        TextView chatTitle = new TextView(this);
        chatTitle.setText("CAFEÍNA");
        chatTitle.setTextColor(TEXT);
        chatTitle.setTextSize(16);
        chatTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        chatTitle.setGravity(Gravity.CENTER_VERTICAL);
        compactHeader.addView(chatTitle,
            new LinearLayout.LayoutParams(0, dp(42), 1f));

        chatSurface.addView(compactHeader, matchWrap());
        chatSurface.addView(
            aiChatPanel,
            new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f));

        DrawerLayout.LayoutParams contentParams =
            new DrawerLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT);
        drawer.addView(chatSurface, contentParams);

        LinearLayout drawerPanel = buildAiDrawer(drawer);
        DrawerLayout.LayoutParams drawerParams =
            new DrawerLayout.LayoutParams(
                dp(304),
                ViewGroup.LayoutParams.MATCH_PARENT);
        drawerParams.gravity = Gravity.START;
        drawer.addView(drawerPanel, drawerParams);

        screenHost.addView(
            drawer,
            new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private LinearLayout buildAiDrawer(DrawerLayout drawer) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(PANEL);
        root.setPadding(dp(16), dp(18), dp(16), dp(16));

        TextView title = new TextView(this);
        title.setText("OPÇÕES DA IA");
        title.setTextColor(TEXT);
        title.setTextSize(17);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title, matchWrap());

        TextView hint = new TextView(this);
        hint.setText("Deslize para a esquerda ou toque fora para fechar.");
        hint.setTextColor(MUTED);
        hint.setTextSize(12);
        LinearLayout.LayoutParams hintParams = matchWrap();
        hintParams.setMargins(0, dp(4), 0, dp(14));
        root.addView(hint, hintParams);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(body,
            new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll,
            new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f));

        TextView modelTitle = new TextView(this);
        modelTitle.setText("Modelo local");
        modelTitle.setTextColor(TEXT);
        modelTitle.setTextSize(14);
        modelTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        body.addView(modelTitle, matchWrap());

        localModelStatus = new TextView(this);
        localModelStatus.setText(localModelImportInProgress
            ? "Importando modelo para o armazenamento privado…"
            : localModelMessage);
        localModelStatus.setTextColor(MUTED);
        localModelStatus.setTextSize(12);
        LinearLayout.LayoutParams modelStatusParams = matchWrap();
        modelStatusParams.setMargins(0, dp(4), 0, dp(10));
        body.addView(localModelStatus, modelStatusParams);

        localModelImportButton = makeButton(
            localModelImportInProgress ? "Importando modelo…" : "Importar modelo GGUF",
            PANEL_2);
        localModelImportButton.setEnabled(!localModelImportInProgress);
        localModelImportButton.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            requestImportLocalModel();
        });
        addAiDrawerButton(body, localModelImportButton);

        localModelSelectButton = makeButton("Selecionar modelo ativo", PANEL_2);
        localModelSelectButton.setEnabled(
            !localModelImportInProgress && !localModelRuntimeInProgress);
        localModelSelectButton.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            requestSelectLocalModel();
        });
        addAiDrawerButton(body, localModelSelectButton);

        localModelTestButton = makeButton(
            localModelRuntimeInProgress ? "Testando modelo…" : "Testar modelo local",
            ACCENT);
        localModelTestButton.setEnabled(
            !localModelImportInProgress
                && !localModelRuntimeInProgress
                && !selectedLocalModelFileName().isEmpty());
        localModelTestButton.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            testSelectedLocalModel();
        });
        addAiDrawerButton(body, localModelTestButton);

        localPlannerButton = makeButton("Testar planejador local", PANEL_2);
        localPlannerButton.setEnabled(
            !localModelImportInProgress
                && !localModelRuntimeInProgress
                && !selectedLocalModelFileName().isEmpty());
        localPlannerButton.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            startActivity(new Intent(this, LaboratoryAiLocalPlannerActivity.class));
        });
        addAiDrawerButton(body, localPlannerButton);

        TextView advancedTitle = new TextView(this);
        advancedTitle.setText("Laboratório e diagnóstico");
        advancedTitle.setTextColor(TEXT);
        advancedTitle.setTextSize(14);
        advancedTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams advancedParams = matchWrap();
        advancedParams.setMargins(0, dp(16), 0, dp(6));
        body.addView(advancedTitle, advancedParams);

        Button permissions = makeButton("Permissões da IA", PANEL_2);
        permissions.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            startActivity(new Intent(this, LaboratoryAiPermissionsActivity.class));
        });
        addAiDrawerButton(body, permissions);

        Button goalLocks = makeButton("Goal Locks", PANEL_2);
        goalLocks.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            startActivity(new Intent(this, LaboratoryAiTaskContractsActivity.class));
        });
        addAiDrawerButton(body, goalLocks);

        Button diagnostics = makeButton("Diagnóstico das IAs", PANEL_2);
        diagnostics.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            startActivity(new Intent(this, LaboratoryAiDiagnosticsActivity.class));
        });
        addAiDrawerButton(body, diagnostics);

        TextView conversationTitle = new TextView(this);
        conversationTitle.setText("Conversa e ação atual");
        conversationTitle.setTextColor(TEXT);
        conversationTitle.setTextSize(14);
        conversationTitle.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams conversationParams = matchWrap();
        conversationParams.setMargins(0, dp(16), 0, dp(6));
        body.addView(conversationTitle, conversationParams);

        Button clearChat = makeButton("Limpar conversa", PANEL_2);
        clearChat.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            aiChatPanel.requestClearConversation();
        });
        addAiDrawerButton(body, clearChat);

        Button actionDiagnostic = makeButton("Diagnóstico da ação", PANEL_2);
        actionDiagnostic.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            aiChatPanel.requestCurrentActionDiagnostic();
        });
        addAiDrawerButton(body, actionDiagnostic);

        Button timeline = makeButton("Linha do tempo da ação", PANEL_2);
        timeline.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            aiChatPanel.requestCurrentActionTimeline();
        });
        addAiDrawerButton(body, timeline);

        Button report = makeButton("Copiar relatório técnico", PANEL_2);
        report.setOnClickListener(v -> {
            drawer.closeDrawer(Gravity.START);
            aiChatPanel.requestCurrentActionSupportReport();
        });
        addAiDrawerButton(body, report);

        return root;
    }

    private void addAiDrawerButton(LinearLayout parent, Button button) {
        button.setAllCaps(false);
        button.setTextSize(13);
        LinearLayout.LayoutParams params = matchWrap();
        params.setMargins(0, 0, 0, dp(8));
        parent.addView(button, params);
    }
'''

main = splice_once(
    main,
    "    private void showSection(String name) {",
    "\n\n\n\n    private void openWorld() {",
    new_section,
    "MainActivity showSection",
)
main_path.write_text(main, encoding="utf-8")

chat_path = Path("executor-app/app/src/main/java/com/cafeina/executor/LaboratoryAiChatPanel.java")
chat = chat_path.read_text(encoding="utf-8")

heading_start = chat.find('        TextView heading = text("CONVERSA COM A CAFEÍNA", 15, FG, true);')
heading_end = chat.find('        currentActionStatus = text("", 13, FG, true);', heading_start)
require(heading_start >= 0 and heading_end >= 0, "Chat heading anchors changed")
chat = chat[:heading_start] + chat[heading_end:]

tech_start = chat.find('        Button clearChat = button("LIMPAR CONVERSA LOCAL", PANEL);')
tech_end = chat.find("        messageScroll = new ScrollView(activity);", tech_start)
require(tech_start >= 0 and tech_end >= 0, "Chat technical-button anchors changed")
hidden_controls = r'''        // Technical controls stay in the side drawer instead of above the chat.
        currentDiagnosticButton = button("DIAGNÓSTICO DA AÇÃO ATUAL", PANEL);
        currentDiagnosticButton.setEnabled(false);
        currentDiagnosticButton.setOnClickListener(v -> showCurrentActionDiagnostic());

        currentTimelineButton = button("LINHA DO TEMPO DA AÇÃO", PANEL);
        currentTimelineButton.setEnabled(false);
        currentTimelineButton.setOnClickListener(v -> showCurrentActionTimeline());

        currentSupportReportButton = button("COPIAR RELATÓRIO TÉCNICO", PANEL);
        currentSupportReportButton.setEnabled(false);
        currentSupportReportButton.setOnClickListener(v -> copyCurrentActionSupportReport());

'''
chat = chat[:tech_start] + hidden_controls + chat[tech_end:]

old_input = "        input.setImeOptions(EditorInfo.IME_ACTION_SEND);\n        input.setBackgroundTintList(ColorStateList.valueOf(MUTED));\n"
new_input = "        input.setImeOptions(EditorInfo.IME_ACTION_SEND);\n        GradientDrawable inputBackground = new GradientDrawable();\n        inputBackground.setColor(PANEL);\n        inputBackground.setCornerRadius(dp(22));\n        input.setBackground(inputBackground);\n        input.setPadding(dp(14), dp(10), dp(14), dp(10));\n"
require(chat.count(old_input) == 1, "Chat input style anchor changed")
chat = chat.replace(old_input, new_input, 1)

old_send = "        sendButton = button(\"ENVIAR\", ACCENT);\n        sendButton.setOnClickListener(v -> sendCurrent());\n        LayoutParams sendParams =\n            new LayoutParams(dp(92), ViewGroup.LayoutParams.WRAP_CONTENT);\n"
new_send = "        sendButton = button(\"↑\", ACCENT);\n        sendButton.setTextSize(20);\n        sendButton.setContentDescription(\"Enviar mensagem\");\n        sendButton.setOnClickListener(v -> sendCurrent());\n        LayoutParams sendParams =\n            new LayoutParams(dp(52), dp(48));\n"
require(chat.count(old_send) == 1, "Chat send-button anchor changed")
chat = chat.replace(old_send, new_send, 1)

close_marker = "    public void close() {"
wrappers = r'''    public void requestClearConversation() {
        confirmClearConversation();
    }

    public void requestCurrentActionDiagnostic() {
        if (!hasCurrentActionForMenu()) {
            android.widget.Toast.makeText(activity, "Ainda não existe uma ação atual", android.widget.Toast.LENGTH_SHORT).show();
            return;
        }
        showCurrentActionDiagnostic();
    }

    public void requestCurrentActionTimeline() {
        if (!hasCurrentActionForMenu()) {
            android.widget.Toast.makeText(activity, "Ainda não existe uma ação atual", android.widget.Toast.LENGTH_SHORT).show();
            return;
        }
        showCurrentActionTimeline();
    }

    public void requestCurrentActionSupportReport() {
        if (!hasCurrentActionForMenu()) {
            android.widget.Toast.makeText(activity, "Ainda não existe uma ação atual", android.widget.Toast.LENGTH_SHORT).show();
            return;
        }
        copyCurrentActionSupportReport();
    }

    private boolean hasCurrentActionForMenu() {
        synchronized (persistedEntries) {
            return workflowContractId != null && !workflowContractId.isEmpty();
        }
    }

'''
require(chat.count(close_marker) == 1, "Chat public API anchor changed")
chat = chat.replace(close_marker, wrappers + close_marker, 1)

old_button_helper = "    private Button button(String label, int color) {\n        Button result = new Button(activity);\n        result.setText(label);\n        result.setTextColor(FG);\n        result.setTextSize(12);\n        result.setBackgroundTintList(\n            ColorStateList.valueOf(color));\n        return result;\n    }\n"
new_button_helper = "    private Button button(String label, int color) {\n        Button result = new Button(activity);\n        result.setText(label);\n        result.setTextColor(FG);\n        result.setTextSize(12);\n        result.setAllCaps(false);\n        result.setMinHeight(dp(44));\n        result.setPadding(dp(14), dp(8), dp(14), dp(8));\n        GradientDrawable background = new GradientDrawable();\n        background.setColor(color);\n        background.setCornerRadius(dp(18));\n        result.setBackground(background);\n        return result;\n    }\n"
require(chat.count(old_button_helper) == 1, "Chat button helper anchor changed")
chat = chat.replace(old_button_helper, new_button_helper, 1)

chat_path.write_text(chat, encoding="utf-8")

print("AI UI migration applied with all anchors verified")
