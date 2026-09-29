# CAFEÍNA Android — início do aplicativo

Esta é a base do **aplicativo Android instalável** da CAFEÍNA, não uma nova sequência T de testes Godot.

## Funciona nesta base

- Shell nativo com as áreas IA, CÓDIGO, MUNDO, 3D e SISTEMA.
- CÓDIGO reutiliza o runtime Luau nativo já implementado: editor local, abas, executar, console, salvar, carregar e Auto Execute explícito.
- Editor com fonte de 17 sp e console de 14 sp, sem depender de editar o código na interface do Godot.
- SISTEMA permite criar, listar e **abrir projetos no editor**; scripts, Auto Execute e arquivos do runtime ficam isolados por projeto.
- O projeto ativo é restaurado ao reabrir o app e é possível voltar aos scripts antigos sem migração.
- Controle A−/A+ ajusta o tamanho da fonte do código entre 14 e 26 sp e guarda a preferência.
- EXPORTAR ZIP e IMPORTAR ZIP usam o seletor de arquivos nativo do Android; cada backup contém os scripts salvos do projeto ativo.
- A importação valida nomes, quantidade, tamanho e UTF-8 antes de gravar; nomes já existentes são renomeados, sem sobrescrever o original ou ativar Auto Execute.
- O aplicativo bloqueia a troca de projeto e a importação/exportação se houver alterações não salvas.
- O app mantém o mesmo applicationId (`com.cafeina.executor`) para preservar os arquivos privados de instalações anteriores.
- Nenhuma migração ou exclusão automática dos scripts antigos.

## Ainda não integrado

- A aba MUNDO abre uma cena Godot 4.7 dentro do APK, com os 11 blocos, personagem, colisão, gravidade 15 e controles de toque. A posição, os tamanhos e as cores dos 11 blocos seguem o arquivo `scripts/world_real.luau` do projeto T14 recebido.
- A GDExtension Luau e o anti-cheat específicos do T14 **ainda não foram integrados** à nova cena; ela é o ponto de entrada 3D do aplicativo, não uma revalidação do T14.
- Execução de Luau na cena Godot, anti-cheat do T14, interface da IA e ferramentas de edição 3D ainda precisam ser integradas.
- O MUNDO usa a biblioteca oficial `org.godotengine:godot:4.7.0.stable` em uma Activity separada, dentro do mesmo aplicativo, sem passar pelo editor Godot.
- Projetos novos usam `files/projects/<id>/scripts` e `runtime-fs`; os scripts existentes continuam em `files/scripts` e podem ser reabertos pela opção **Scripts antigos**.
- A importação ou cópia de scripts entre projetos ainda não foi implementada; nenhuma migração automática é feita.

## Build

`cd executor-app && gradle :app:assembleDebug`

A rotina `.github/workflows/executor-app-ci.yml` executa testes automatizados e gera o APK debug como artefato de CI. Não exigir nova sequência de testes manuais no Godot.
