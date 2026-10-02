# Validação do fluxo de ação da IA no Android

Esta lista é o gate manual da fundação atual do Laboratório da CAFEÍNA antes de avançar para ferramentas mais complexas.

## Pré-condições

- Um GGUF válido foi importado e selecionado como modelo ativo.
- O botão `TESTAR PLANEJADOR LOCAL` habilita imediatamente após a seleção do GGUF e volta ao estado bloqueado quando não existe modelo ativo.
- O planejador oferece `CRIAR GOAL LOCK` diretamente quando ainda não existe um contrato disponível, sem exigir voltar para outra tela.
- `diagnostic-roundtrip @ 1.0.0` foi preparado como CANDIDATE.
- A promoção CANDIDATE -> STABLE foi aprovada pelo usuário.
- O acesso da IA à STABLE foi concedido em uma segunda autorização explícita.

## Ciclo principal

1. Enviar no chat um pedido classificado como AÇÃO.
2. Confirmar a criação do Goal Lock com objetivo, modo, ferramentas e orçamento corretos.
3. Gerar o plano pelo modelo local sem executar ferramentas durante o planejamento.
4. Validar o plano antes da preparação da Testadora.
5. Confirmar separadamente a execução da Testadora.
6. Executar `diagnostic-roundtrip` pelo worker isolado.
7. Confirmar resultado e consumo correto do Goal Lock.
8. Conferir `AÇÃO ATUAL`, progresso, orçamento e estado terminal.
9. Conferir `LINHA DO TEMPO DA AÇÃO` do Goal Lock até o resultado.
10. Gerar `COPIAR RELATÓRIO TÉCNICO` e confirmar que objetivo exato, prompt e conteúdo sensível não são exportados.

## Interrupções e recuperação

- Pausar e continuar durante uma ação suportada.
- Cancelar durante planejamento e durante Testadora sem deixar execução órfã.
- Fechar e reabrir o app e confirmar restauração do chat e do estado operacional.
- Revisar sessão órfã/interrompida sem retomada automática.
- Girar a tela do planejador durante processamento e confirmar preservação do estado.

## Critério para avançar

A fundação só é considerada validada quando o ciclo principal passa no aparelho real sem bypass de permissão, sem consumo prematuro do Goal Lock, sem perda de estado e com diagnóstico suficiente para localizar qualquer falha.
