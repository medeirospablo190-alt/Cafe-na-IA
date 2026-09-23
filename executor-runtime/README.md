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
