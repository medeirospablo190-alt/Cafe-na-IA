# CAFEÍNA Luau Runtime — Phase 1

Primeiro bloco do mecanismo de execução do novo app. Este diretório é independente do coletor e não injeta código em Roblox nem modifica o APK do Delta.

## O que já faz

- compila fonte Luau com `luau_compile`;
- carrega bytecode com `luau_load`;
- executa em thread isolada com `luaL_sandbox` + `luaL_sandboxthread`;
- captura `print` e `warn`;
- devolve valores retornados pelo script;
- diferencia erro de compilação e erro de runtime;
- interrompe loops longos por timeout;
- possui bridge JNI para Android (`nativeExecute`).

## Segurança desta fase

A VM não recebe API de Roblox, injeção de processo, filesystem, clipboard ou rede. Só as bibliotecas padrão do Luau sandboxado e as funções `print`/`warn` substituídas pelo host.

## Dependência Luau

O CMake fixa o Luau oficial no commit:

`653fa9cb7a6b379651292ce1b7e4649b6e12ab02`

Isso evita mudanças inesperadas de API durante o desenvolvimento.

## Build no notebook

Requer CMake, compilador C/C++ e Git.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

Teste manual:

```bash
./build/cafeina_luau_cli "print('oi') return 10 * 2"
```

## Android

Quando compilado pelo Android NDK (`ANDROID=TRUE`), o CMake gera `libcafeina_luau_jni.so`.

A classe `android/com/cafeina/runtime/LuauBridge.java` expõe:

```java
LuauBridge.nativeExecute(source, timeoutMs)
```

O retorno é JSON com `ok`, `output`, `error`, `elapsedMs` e `returns`.

## Próxima fase

Ligar o runtime ao shell Android do menu reconstruído: editor, botão EXECUTE, console, abas `.lua` e armazenamento local controlado pelo próprio app.


## Phase 8 — API local de arquivos sandboxada

O runtime agora aceita opcionalmente um diretório de arquivos fornecido pelo host.

Quando o host não fornece esse diretório, `fs` não existe no ambiente Luau. Quando fornece, os scripts recebem apenas:

- `fs.write(name, content)`;
- `fs.read(name)`;
- `fs.exists(name)`;
- `fs.list()`.

Regras:

- somente nomes de arquivo planos;
- sem `/`, `\\`, `..` ou nomes ocultos;
- symlinks são rejeitados;
- máximo de 1 MiB por arquivo;
- no máximo 128 nomes retornados por listagem;
- não há delete nesta fase;
- a API não alcança `files/scripts`, `autoexec.list` ou outras áreas do app;
- a bridge Android expõe `nativeExecuteWithFiles(source, timeoutMs, sandboxRoot)`, mantendo `nativeExecute` compatível e sem filesystem.


## Phase 8.5 — runtime platform execution contract

The runtime now has a canonical host-side execution contract without changing the existing Android/JNI behavior.

New public types:

- `ExecutionRequest`: source + limits + execution context;
- `ExecutionContext`: host-owned execution/project identifiers plus explicit host access;
- `ExecutionResult`: semantic alias for the existing `RuntimeResult`.

Compatibility is preserved:

- `execute(source, limits, hostAccess)` still works and delegates to `ExecutionRequest`;
- `nativeExecute()` is unchanged;
- `nativeExecuteWithFiles()` is unchanged;
- the sandboxed `fs` API is still opt-in and scoped to the same host-provided directory.

The new metadata is host-side only and is not exposed automatically as Luau globals. This is the foundation for later capability, task/cancellation, project and Test World APIs without coupling the C++ runtime to Android UI classes.


## Phase 8.6 — capability system foundation

Host resources are now gated by explicit runtime capabilities.

Initial capability:

- `RuntimeCapability::Files`.

Rules:

- an `ExecutionRequest` does not receive host APIs by default;
- providing `hostAccess.filesRoot` alone does not expose `fs`;
- the request must also explicitly grant the `FILES` capability;
- granting `FILES` without a sandbox root fails closed before script execution;
- legacy `execute(source, limits, hostAccess)` callers preserve Phase 8 behavior by automatically granting only `FILES` when a non-empty `filesRoot` is supplied;
- JNI and Android APIs remain unchanged.

This establishes least-privilege capability gating before future APIs such as World, UI, Test or Network are introduced.


## Phase 8.7 — cancellation core

Canonical executions can now receive a host-owned, thread-safe `CancellationToken`.

Behavior:

- the token is optional and one-shot;
- a request cancelled before execution fails closed with `execution cancelled`;
- a running Luau loop is interrupted through the same VM interrupt mechanism used by timeouts;
- cancellation is checked before timeout so an explicit user stop is reported as cancellation;
- the token uses an atomic flag and has no Android UI dependency;
- legacy executor/JNI calls remain unchanged when no token is supplied.

The smoke suite covers both pre-start cancellation and cancellation of a running infinite loop from another host thread. This prepares the runtime for future PAUSE/STOP task controls without putting task management inside the Luau VM.


## World capability bridge

The runtime can now receive a shared `WorldService` through explicit host access and grant `RuntimeCapability::World`.

Least-privilege rules:

- a `WorldService*` without the WORLD capability is ignored;
- WORLD capability without a service fails closed before script execution;
- without WORLD, the Luau global `World` does not exist;
- the existing Android JNI entry points do not grant WORLD and therefore keep their current behavior.

Initial Luau API:

```lua
local house = World.create("House")
local door = World.create("Door")

World.setParent(door, house)
World.setPosition(house, 0, 5, 0)
World.setRotation(house, 0, 45, 0)
World.setScale(house, 2, 2, 2)

local object = World.get(house)
local children = World.children(house)

World.setName(house, "MainHouse")
World.remove(door)
```

Object IDs cross the Luau boundary as decimal strings rather than floating-point numbers. This preserves full 64-bit identity and avoids precision loss as worlds grow.

The bridge talks only to the synchronized `WorldService`. It does not expose Android internals, renderer state, raw filesystem access or direct `World*` mutation.


## Android shared World bridge

Android now has an explicit shared World path for executions that opt into it.

New JNI surface:

- `nativeExecuteWithFilesAndWorld(...)`
- `nativeRenderSceneSnapshot()`
- `nativeResetWorld()`

The original `nativeExecute()` and `nativeExecuteWithFiles()` remain unchanged for compatibility.

`nativeExecuteWithFilesAndWorld()` builds a canonical `ExecutionRequest`, grants FILES only when a sandbox root is present, explicitly grants WORLD, and supplies one process-local synchronized `WorldService`.

The same service is used to build immutable `RenderScene` snapshots for the Android preview.

### Luau convenience

```lua
local part = World.createPart("Box")
World.setPosition(part, 0, 1, 0)
World.setRotation(part, 0, 45, 0)
World.setScale(part, 2, 2, 2)
```

`World.createPart()` creates one World object and atomically attaches a visible Box `MeshComponent`. If attaching the mesh fails, the object is removed again instead of leaving a partial renderable.
