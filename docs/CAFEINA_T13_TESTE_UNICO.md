# CAFEÍNA T13 — UMA ÚNICA RODADA DE VALIDAÇÃO

## Decisão de produto

Parar a sequência de testes isolados. Construir a próxima versão do aplicativo Godot + Luau e concentrar a validação final no Android em **uma sessão guiada**, disparada pelo botão **TESTAR TUDO**. Executar verificações automatizadas durante o desenvolvimento; não exigir que o usuário digite vários códigos ou abra pacotes de teste separados.

**Este documento é o plano de implementação, não um registro de testes já executados.** O botão, o orquestrador e o pacote T13 ainda precisam ser implementados no código real da T12.1.

## Ponto de partida confirmado pelo usuário em 29/09/2026

- Na T12.1, o teclado abriu, o editor aceitou texto e o arquivo continuou salvo depois de reiniciar a execução do projeto.
- A confirmação visual do botão SALVAR .LUAU não apareceu; tratar como defeito de interface ainda pendente, mesmo que a persistência tenha funcionado.
- Joystick e câmera continuaram operando após a correção de toque.
- `world check` retornou o mundo, personagem OK, 11 blocos, gravidade 15.0, revisão 13 e 0,33 ms, conforme leitura do usuário.
- **Ainda não foi comprovado nesta T12.1 que o script salvo no editor é executado pela ponte Luau e modifica o mundo**. Não confundir o comando do console com essa prova.
- A validação do bloqueio de movimentação real do anti-cheat T11 no Android permaneceu pendente no histórico. O teste sintético não substitui esse resultado.

## Arquitetura do teste único

Um coordenador Godot, isolado do loop normal de jogo, percorre todos os módulos e gera um único relatório local (`user://diagnostics/t13-<id>.json`, mais um resumo legível). Cada prova tem ID, pré-condições, resultado esperado, observação, duração e estado: `PASSOU`, `FALHOU`, `NÃO IMPLEMENTADO` ou `INCONCLUSIVO`. **Nunca transformar ausência de sinal em sucesso.** Guardar o estado antes da execução e restaurar mapa, personagem, gravidade, controles e scripts depois. Nenhum teste toca no cliente oficial Roblox nem em dados privados de outros apps.

### Provas automáticas dentro da mesma execução

1. **Inicialização e integridade:** projeto abre, cena principal e bibliotecas Luau Android ARM64 carregam sem fallback simulado; componentes essenciais são identificados.
2. **Editor e armazenamento:** criar um script temporário curto, salvar, ler o arquivo exato, comparar conteúdo e confirmar visualmente o salvamento; não sobrescrever o rascunho real do usuário.
3. **Ponte Luau → Godot:** compilar e executar o script temporário no runtime real, registrar `print` e usar somente a API de mundo efetivamente exposta pelo projeto para criar/alterar um objeto de teste; ler o estado no Godot e desfazer a alteração. Se a API necessária não existir, marcar `NÃO IMPLEMENTADO` e abrir uma tarefa de desenvolvimento; não inventar resultado.
4. **Mundo e física:** verificar personagem, blocos, gravidade, colisão, criação/remoção controlada de objeto e retorno ao estado inicial.
5. **Console e navegação:** enviar comandos suportados ao mesmo despachante do botão EXECUTAR COMANDO; confirmar resposta, alternância entre as cinco áreas e preservação de estado. Não contar um `world check` como execução de script do editor.
6. **Segurança do próprio laboratório:** testar movimento legítimo sem bloqueios indevidos e tentativas controladas de movimento irregular por uma interface interna de teste. Registrar separadamente detecção, bloqueio real e falsos positivos; simulação isolada recebe rótulo próprio. Não testar anti-cheat de jogos de terceiros.
7. **Robustez:** executar um script inválido e um script que atinge o limite de tempo de forma isolada; conferir mensagem de erro, interrupção, recuperação e preservação dos arquivos. Medir tempo e consumo apenas onde houver instrumentação real.
8. **Persistência de sessão:** registrar sessão de teste e rascunho em disco e verificar novamente após reinício real do aplicativo. Quando um reinício real não puder ser automatizado com segurança no Android, o mesmo fluxo solicitará **uma única reabertura** e continuará de onde parou.

### O mínimo de interação humana

Abrir a versão integrada e tocar uma vez em **TESTAR TUDO**. Durante a mesma sessão, se solicitado, realizar um movimento curto no joystick e girar a câmera; esses gestos de toque físico não devem ser declarados validados por uma simulação. Se aparecer a etapa de persistência, reabrir o app uma vez. Ao final, um painel apresenta `PASSOU/FALHOU/NÃO IMPLEMENTADO/INCONCLUSIVO` para cada módulo e permite compartilhar apenas o relatório técnico sem credenciais ou arquivos pessoais.

## Critério de conclusão

A rodada T13 só é concluída quando existe relatório verificável do celular. Qualquer item não implementado, falha ou resultado inconclusivo aparece claramente no relatório e vira correção de desenvolvimento, não mais um pedido de teste isolado ao usuário. O app pode continuar em desenvolvimento apesar de pendências, mas não será chamado de integrado/validado se a ponte Luau real, o salvamento ou os controles essenciais falharem.

## Ordem de implementação

1. Importar o **projeto-fonte exato T12.1** para `app/godot/` nesta branch, preservando versões e bibliotecas; o ZIP da T12.1 não está atualmente na raiz da `main` do repositório. Não reconstruir o projeto a partir de descrições quando o fonte real estiver disponível.
2. Corrigir retorno visível do salvamento e conectar o editor à ponte Luau real, com execução limitada por permissões e tempo.
3. Implementar `T13OneShotRunner`, os adaptadores para APIs existentes e a coleta de resultados; testes isolados de desenvolvimento podem rodar automaticamente, sem tarefa para o usuário.
4. Empacotar a versão integrada e executar a única rodada final no Android. Só depois avaliar o próximo incremento de IA, modelagem 3D e construção de jogos.

**Escopo:** a T13 valida a base integrada disponível; não afirma que IA local, modelador 3D completo, criador automático de jogos ou APK final já estejam prontos.
