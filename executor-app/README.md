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


## Phase 4 — armazenamento local de scripts

O app agora possui uma camada de armazenamento local independente da interface.

- diretório privado do app: `files/scripts`;
- somente nomes `.lua` validados;
- bloqueio de path traversal e caracteres de controle;
- limite inicial de 2 MiB por script;
- gravação em arquivo temporário, `fsync` e commit por move atômico quando disponível;
- leitura UTF-8;
- listagem ordenada;
- arquivos temporários/inválidos são ignorados;
- nenhum script do usuário é apagado automaticamente;
- nenhuma rede, servidor ou banco de dados é usado.

Nesta fase o armazenamento ainda não foi ligado aos botões do editor. Primeiro ele é validado isoladamente por testes JVM e por teste instrumentado no armazenamento interno do Android.


## Phase 5 — SAVE / LOAD local

A interface passa a usar o `ScriptStore` validado na Fase 4.

- SAVE grava somente a aba ativa no armazenamento privado do app;
- LOAD lista somente scripts `.lua` válidos salvos localmente;
- carregar um arquivo abre/ativa uma aba com o nome do arquivo;
- se uma aba aberta tiver conteúdo diferente da versão em disco, o app pede confirmação antes de substituí-la;
- o botão `+` consulta os nomes já salvos e pula nomes ocupados, evitando criar uma aba nova com o mesmo nome de um arquivo antigo;
- operações de disco rodam em executor separado da UI e do runtime;
- erros de armazenamento aparecem no console sem encerrar o app.

O CI também abre a Activity no emulador, altera o editor, toca SAVE e confirma que `script.lua` foi persistido com o conteúdo esperado.


## Phase 6 — restauração e proteção contra perda de alterações

O editor agora trata o estado das abas explicitamente:

- scripts `.lua` já salvos são restaurados como abas ao abrir o app;
- o editor fica temporariamente bloqueado durante a restauração inicial para impedir sobrescrita por corrida;
- uma aba alterada recebe `*` no nome;
- SAVE só remove o `*` quando o conteúdo confirmado em disco corresponde ao snapshot salvo;
- cada aba possui botão de fechamento;
- uma aba alterada só fecha após escolher **Salvar e fechar**, **Fechar sem salvar** ou **Cancelar**;
- o último tab não pode ser fechado, evitando deixar o editor sem estado válido;
- fechar uma aba não apaga o arquivo salvo em disco;
- nenhum script é executado automaticamente na restauração.

Continuamos sem servidor e sem banco de dados. Toda essa fase usa exclusivamente o armazenamento privado do Android.


## Phase 7 — Auto Execute local e explícito

O Auto Execute continua totalmente local e opt-in.

- somente scripts `.lua` já salvos podem ser marcados;
- uma aba com alterações não salvas precisa ser salva antes de alterar o Auto Execute;
- a lista de opt-in fica em `files/autoexec.list`, separada do conteúdo dos scripts;
- no máximo 32 scripts podem ser marcados;
- o startup ignora nomes inválidos e não executa arquivos que não existem mais;
- nenhum script novo entra no Auto Execute automaticamente;
- cada execução continua passando pelo mesmo runtime Luau sandboxado e pelo mesmo timeout;
- o console identifica cada execução com `[AUTOEXEC] nome.lua`;
- falha em um script não impede os próximos da lista de serem tentados;
- nenhuma rede, servidor ou banco de dados é usado.

O CI salva um script de teste, marca explicitamente esse arquivo, reabre a Activity no emulador e exige a saída `autoexec-phase7-ok` e o retorno `123`.


## Phase 8 — arquivos do runtime em sandbox própria

Execuções manuais e Auto Execute agora podem usar uma API local de arquivos, mas apenas dentro de:

`files/runtime-fs`

Essa pasta é separada de:

- `files/scripts`;
- `files/autoexec.list`;
- demais arquivos privados do app.

Exemplo Luau:

```lua
fs.write("dados.txt", "42")
print(fs.read("dados.txt"))
print(fs.exists("dados.txt"))
print(table.concat(fs.list(), ", "))
```

Não existe acesso ao armazenamento geral do Android, servidor, banco de dados ou rede.


## Phase 8.8 — Project Core foundation

A project storage foundation now exists independently from the current editor storage.

Each project lives under:

`files/projects/<project-id>/`

Initial layout:

- `scripts/`
- `runtime-fs/`
- `worlds/`
- `assets/`
- `snapshots/`
- `.cafeina-project` version marker

Rules:

- project IDs are stable storage identifiers and are validated separately from future display names;
- traversal, hidden IDs, uppercase IDs and unsafe paths are rejected;
- only directories with a valid CAFEÍNA marker and the complete required layout are listed as projects;
- unsupported/corrupted marker versions fail closed;
- duplicate creation never replaces an existing project;
- partial creation is cleaned up only when that new project creation itself fails;
- the Project Core is currently isolated and is not yet wired into the editor, Auto Execute or existing `files/scripts` / `files/runtime-fs` data.

Keeping the existing storage untouched avoids a destructive migration before project selection, migration and rollback rules are defined and tested.


## Phase 11 — Android render backend bootstrap

The app now has an isolated `WorldPreviewActivity` that proves the Android GPU/render lifecycle without making the current editor or World Core depend directly on a graphics backend.

Initial backend:

- Google Filament `1.75.1`;
- `filament-android` for the rendering runtime;
- `filamat-android` only for this bootstrap phase so the preview material can be generated at runtime instead of committing a precompiled binary material.

The editor exposes a `WORLD PREVIEW` button that opens the separate preview Activity.

The bootstrap currently renders a small vertex-colored triangle. It intentionally does **not** create a second mutable world model and is not yet connected to `RenderScene`.

Architecture remains:

`WorldService -> WorldState -> RenderScene -> Android graphics backend`

The next bridge will feed immutable RenderScene snapshots into the Android backend.

### Lifecycle validation

The preview follows Filament's Android surface lifecycle:

- Filament initialized before API use;
- `SurfaceView` managed with `UiHelper`;
- swap chain created/destroyed with the native window;
- frame scheduling stops on pause;
- GPU resources are explicitly destroyed;
- an Android instrumentation test launches the preview and requires successful Filament/material/mesh initialization on the emulator.

Runtime material compilation is a bootstrap convenience. Once the backend path is stable, the intended optimization is to ship a material precompiled with the matching Filament release and remove `filamat-android` from normal runtime builds.


## Phase 11.1 — shared World -> RenderScene -> Filament bridge

The editor and preview now use the same native World state.

Manual executions and Auto Execute call `nativeExecuteWithFilesAndWorld()`, so authorized Luau code can mutate the shared synchronized `WorldService`.

The preview does not own a second mutable scene model. When opened it requests an immutable `RenderScene` snapshot from JNI and renders that snapshot with Filament.

Current end-to-end path:

```text
Luau
  -> RuntimeCapability::World
  -> shared WorldService
  -> WorldState
  -> RenderSceneBuilder
  -> RenderScene JSON snapshot
  -> WorldPreviewActivity
  -> Filament entities
```

Initial visual support is deliberately narrow:

- `World.createPart()` creates a visible Box MeshComponent;
- Box RenderItems are drawn by the Android preview;
- position, rotation and scale are applied;
- unsupported future primitive types are skipped rather than silently rendered as the wrong shape.

The instrumentation test resets the shared world, creates a part from Luau, verifies the native RenderScene snapshot, launches the Filament Activity, and requires the Activity to report exactly one rendered item.


### Hierarchical preview transforms

The Android preview consumes Render Core's resolved `worldMatrix` directly when available. It keeps the older local transform fields only as a compatibility fallback.

The emulator integration test creates a logical parent and a renderable child from Luau, parents the child, applies local positions, and verifies the composed world translation before Filament initialization succeeds.


## Phase 11.3 — project world document persistence

A CAFEÍNA project can now persist the native shared World without moving world authority into Java.

Storage:

`files/projects/<project-id>/worlds/main.cafeina-world.json`

`WorldDocumentStore` provides:

- UTF-8 storage;
- 16 MiB size guard aligned with the native world format limit;
- same-directory temporary file;
- fsync before commit;
- atomic replace when supported;
- fallback replace when atomic move is unavailable;
- symlink rejection;
- no leftover temp file after successful save.

`ProjectWorldPersistence` coordinates:

`native World export -> atomic project file`

and:

`project file -> validated native World import`

The coordinator uses an injectable bridge so JVM tests do not load the native library.

Android instrumentation verifies the complete sequence:

1. Luau creates a renderable World object;
2. native World exports as CAFEINA_WORLD v2;
3. World is reset;
4. exported JSON is imported;
5. RenderScene returns the object again with the same transform;
6. malformed JSON is rejected without destroying the restored World.
