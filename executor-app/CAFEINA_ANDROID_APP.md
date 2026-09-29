# CAFEÍNA Android — início do aplicativo

Esta é a base do **aplicativo Android instalável** da CAFEÍNA, não uma nova sequência T de testes Godot.

## Funciona nesta base

- Shell nativo com as áreas IA, CÓDIGO, MUNDO, 3D e SISTEMA.
- CÓDIGO reutiliza o runtime Luau nativo já implementado: editor local, abas, executar, console, salvar, carregar e Auto Execute explícito.
- Editor com fonte de 17 sp e console de 14 sp, sem depender de editar o código na interface do Godot.
- SISTEMA permite criar, listar e inspecionar pastas de projetos locais via ProjectStore existente.
- O app mantém o mesmo applicationId (`com.cafeina.executor`) para preservar os arquivos privados de instalações anteriores.
- Nenhuma migração ou exclusão automática dos scripts antigos.

## Ainda não integrado

- A cena Godot/Luau do T14 não está versionada neste ramo do GitHub e **não está embutida neste APK**.
- Execução de Luau no mundo 3D, interface da IA e ferramentas 3D ainda precisam ser integradas.
- O editor atual ainda usa `files/scripts`, separado dos diretórios novos em `files/projects`.

## Build

`cd executor-app && gradle :app:assembleDebug`

A rotina `.github/workflows/executor-app-ci.yml` executa testes automatizados e gera o APK debug como artefato de CI. Não exigir nova sequência de testes manuais no Godot.
