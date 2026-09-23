# CAFEÍNA Runtime App — Phase 2

Primeiro shell Android do runtime Luau validado na Fase 1.

## Escopo desta fase

- app Android nativo separado;
- editor Luau monoespaçado;
- botão EXECUTE;
- botão CLEAR;
- console de saída;
- execução fora da UI thread;
- bridge JNI reutilizada de `executor-runtime/android`;
- runtime nativo vindo diretamente de `../executor-runtime`.

Ainda não inclui Script Hub, abas, arquivos, temas, Auto Execute ou integração com Roblox.

## Fluxo

`Editor -> LuauBridge.nativeExecute -> libcafeina_luau_jni.so -> LuauRuntime -> JSON -> Console`

## ABI inicial

A Fase 2 compila `arm64-v8a`, suficiente para validar o APK em Android ARM64. Suporte adicional de ABI deve entrar em PR separado depois que este fluxo básico estiver estável.


## Phase 3 — abas em memória

A interface agora suporta múltiplas abas `.lua` sem persistência em disco:

- `script.lua` é a aba inicial;
- o botão `+` cria `script1.lua`, `script2.lua` e assim por diante;
- trocar de aba preserva o conteúdo de cada editor em memória;
- EXECUTE roda apenas a aba ativa;
- CLEAR limpa apenas a aba ativa.

A lógica de estado das abas vive em `EditorTabs.java` e possui testes unitários independentes da Activity.
