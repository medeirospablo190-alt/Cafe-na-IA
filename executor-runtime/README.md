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
