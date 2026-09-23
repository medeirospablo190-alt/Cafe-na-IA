# CAFEÍNA — PROTOCOLO OPERACIONAL AUTORITATIVO

Atualizado em 2026-09-23.

Este arquivo é a fonte operacional vigente. Ele SUBSTITUI regras operacionais anteriores que produzam micro-updates, polling repetitivo, confirmações redundantes, fragmentação artificial ou parada prematura. Regras técnicas de segurança/arquitetura continuam válidas, mas não controlam quando a conversa para.

## As 6 regras vigentes

1. **Execução contínua por objetivo.** Depois de “começa/continua”, executar blocos grandes e encadear as próximas etapas automaticamente. Commit, PR, merge, CI, teste, fim de etapa e erro corrigível não são motivos para parar.
2. **Analisar antes e agir em lote.** Recuperar estado, dependências e contexto necessários antes do bloco. Agrupar consultas e operações relacionadas. Evitar consulta → pequena ação → consulta → pequena ação.
3. **Resolver internamente.** Erro corrigível é diagnosticado, corrigido e retestado sem devolver o problema ao usuário. CI pendente vira pendência enquanto outro trabalho útil continua. Sem polling repetitivo.
4. **Não narrar o processo.** Nada de micro-status, logs, commits, jobs e informações intermediárias enchendo a tela. Quando houver retorno, apresentar resultados consolidados.
5. **Só parar por dependência real do usuário.** Parar voluntariamente apenas quando faltar decisão, informação, autenticação, ação física ou autorização que realmente só o usuário possa fornecer. Limitações inevitáveis da sessão/plataforma não são conclusão do trabalho.
6. **Continuidade obrigatória entre chats.** Preservar objetivo, arquitetura, decisões, estado real, concluído, pendências e ponto exato de continuação. O próximo chat verifica o estado real e continua dali, sem ressuscitar regras operacionais antigas conflitantes e sem refazer trabalho válido.

## Interpretações obrigatórias

- “PR pequeno” = PR tecnicamente focado; NÃO significa sessão curta.
- CI = gate técnico; NÃO é atividade principal nem motivo de parada.
- Checkpoint = estado recuperável; NÃO é lugar para devolver a conversa.
- “Verificar antes de afirmar” = consultar a fonte necessária no momento adequado; NÃO monitorar continuamente.
- Autorização “continua/começa” persiste para o fluxo já planejado.
- “só responde” = não usar ferramentas.
- “não faça nada por enquanto” = análise/planejamento apenas; sem mutações.
- Pergunta direta durante execução = responder primeiro e continuar se a autorização permanecer.
- Erro corrigível = causa → correção → teste → continuação.
- Ferramentas, commits, PRs, CI e logs são internos ao bloco.
- Relatar resultados, não movimentos.

## NÃO PERDER AO TROCAR DE CHAT

O próximo chat deve ler este protocolo antes de executar. Nenhuma regra operacional antiga conflitante pode recuperar precedência. O handoff deve preservar granularmente decisões, arquitetura, estado GitHub, testes, falhas, correções, infraestrutura, Collector, pendências e sequência exata de continuação.
