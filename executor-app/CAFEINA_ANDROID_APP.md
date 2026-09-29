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

- A cena Godot/Luau do T14 não está versionada neste ramo do GitHub e **não está embutida neste APK**.
- Execução de Luau no mundo 3D, interface da IA e ferramentas 3D ainda precisam ser integradas.
- Projetos novos usam `files/projects/<id>/scripts` e `runtime-fs`; os scripts existentes continuam em `files/scripts` e podem ser reabertos pela opção **Scripts antigos**.
- A importação ou cópia de scripts entre projetos ainda não foi implementada; nenhuma migração automática é feita.

## Build

`cd executor-app && gradle :app:assembleDebug`

A rotina `.github/workflows/executor-app-ci.yml` executa testes automatizados e gera o APK debug como artefato de CI. Não exigir nova sequência de testes manuais no Godot.
