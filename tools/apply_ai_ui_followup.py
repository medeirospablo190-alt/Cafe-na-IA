from pathlib import Path

main_path = Path("executor-app/app/src/main/java/com/cafeina/executor/MainActivity.java")
main = main_path.read_text(encoding="utf-8")
old = '''        if (aiChatPanel == null) {\n            aiChatPanel = new LaboratoryAiChatPanel(this, workspace.id());\n        }\n\n        DrawerLayout drawer = new DrawerLayout(this);\n'''
new = '''        if (aiChatPanel == null) {\n            aiChatPanel = new LaboratoryAiChatPanel(this, workspace.id());\n        }\n        // The chat panel survives section changes. Detach it from the old\n        // drawer before attaching it to the newly rendered IA surface.\n        if (aiChatPanel.getParent() instanceof ViewGroup) {\n            ((ViewGroup) aiChatPanel.getParent()).removeView(aiChatPanel);\n        }\n\n        DrawerLayout drawer = new DrawerLayout(this);\n'''
if main.count(old) != 1:
    raise SystemExit("AI chat reparent anchor changed")
main_path.write_text(main.replace(old, new, 1), encoding="utf-8")

chat_path = Path("executor-app/app/src/main/java/com/cafeina/executor/LaboratoryAiChatPanel.java")
chat = chat_path.read_text(encoding="utf-8")
replacements = [
    (
        '"Ainda não há modelo local ativo. Selecione um GGUF nos "\n                    + "controles logo abaixo do chat e envie a mensagem novamente."',
        '"Ainda não há modelo local ativo. Abra o menu lateral da IA, "\n                    + "selecione um GGUF e envie a mensagem novamente."',
    ),
    (
        '"Não há modelo local ativo para gerar o plano. "\n                    + "Selecione um GGUF nos controles da aba IA."',
        '"Não há modelo local ativo para gerar o plano. "\n                    + "Abra o menu lateral da IA e selecione um GGUF."',
    ),
]
for old_text, new_text in replacements:
    if chat.count(old_text) != 1:
        raise SystemExit("AI drawer guidance anchor changed")
    chat = chat.replace(old_text, new_text, 1)
chat_path.write_text(chat, encoding="utf-8")

print("AI UI follow-up applied with all anchors verified")
