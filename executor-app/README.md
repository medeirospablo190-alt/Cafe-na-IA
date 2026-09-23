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
