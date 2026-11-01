# Roadmap CAFEÍNA — 100 pontos verificáveis

**Fonte oficial:** `../plan/progress.json`. Use `npm --prefix ai-core run progress` a partir da raiz para calcular o progresso. Não confundir percentual de marcos aceitos com percentual de linhas de código.

| Fase | Peso | Critério real para concluir |
| --- | ---: | --- |
| P0 Fundação | 10 | Arquitetura, contratos, segurança, CI GitHub verde |
| P1 Evidências | 15 | Vários lotes V3 e perfis, indexação por jogo, evidências, memória, contradições, privacidade |
| P2 Agentes | 15 | Modelo gratuito substituível, Coordenadora, Investigadora, Pesquisadora, Crítica, Programadora, Testadora e persistência |
| P3 Comunicação | 15 | Menu recebe missões, devolve resultados com autenticação, ack, TTL e idempotência |
| P4 Coletor | 15 | Ferramentas de observação, permissões, limites, auditoria e teste autorizado |
| P5 REA | 10 | REA CLI/MCP rodando em ambiente compatível; adaptador de evidências validado |
| P6 Reconstrução | 10 | Especificações, código Luau novo, build, testes comparativos e PR |
| P7 Roblox | 5 | Rojo, jogo de teste próprio, deploy só com aprovação |
| P8 Qualidade | 5 | Segurança, custos limitados, recuperação e ciclo integrado ponta a ponta |
| **Total** | **100** | **Todos os critérios comprovados com testes e evidências** |

## Primeiro marco, 2026-11-01

- **P0 = 10/10**: estrutura, contratos, documentos e CI verde confirmada: [push](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41345792411) e [PR](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41345820474).
- **P1 = 14/15**: leitura de sessão V3 completa, perfil V1, metadados por jogo, deduplicação, conflitos, relatórios redigidos e CI com [15 lotes reais](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41346427994). A leitura remota e a fusao por GitHub foram testadas; continuam pendentes uma escrita remota real validada e a revisao da privacidade historica.
- **P2 = 8/15**: modelo Qwen2.5 0.5B executado realmente no GitHub Actions (CPU) com dados sinteticos, respostas estruturadas restritas e diario de decisoes validado. Ainda faltam orquestracao persistente, outros agentes, modelo mais capaz e testes de qualidade.
- **P3 a P8 = 0**: apenas planejadas.

**Atual: 32/100; faltam 68 pontos.** Registrar links de CI/PR antes de creditar novos pontos.

## Ordem técnica

1. Finalizar CI da fundação.
2. Processar múltiplos lotes de uma sessão com privacidade e proveniência.
3. Adicionar memória por jogo e relatório de hipóteses.
4. Integrar um modelo gratuito e os agentes.
5. Executar o REA em runner isolado.
6. Criar fila autenticada GitHub → gateway → menu, com confirmação.
7. Adicionar ferramentas permitidas no coletor com autorização.
8. Reconstruir mecânica Luau pequena, compilar e testar.
9. Publicar apenas com aprovação e concluir E2E.

**R$ 0 de novas mensalidades é objetivo, não garantia de acesso ilimitado.** Quando uma cota gratuita acabar, o sistema deve parar a tarefa, não iniciar cobranças.

## Evidência da segunda entrega — 2026-11-01

O CI do AI Core analisou uma sessão histórica de 15 lotes V3, manifesto V3 e perfil persistido de esquema V1. A análise foi executada no runner sem enviar dados brutos para modelos ou publicar seus conteúdos nos logs. A memória local foi testada com fixtures sintéticas de múltiplas sessões, idempotência e conflito.

As propostas emitidas permanecem `PROPOSED` e `executable: false`; modelo de IA e ligação reversa com o Roblox continuam pendentes.

## Incremento: agentes e infraestrutura de memoria

- Quatro agentes possuem contrato de troca de mensagens com passos limitados, sem autonomia ativa no Roblox.
- Há interface opcional para um modelo local compatível com Ollama, testada com respostas simuladas; execução de LLM real continua pendente.
- A sincronização de índices no GitHub valida dados, detecta conflitos e só escreve com opt-in. A branch de memória foi criada, mas nenhuma sessão real foi publicada nela.
- CI inclui um teste read-only de consulta remota à API do GitHub, além de testes de privacidade em fixtures sintéticas.

## Atualizacao verificada — 2026-11-01

- CI do PR com todos os testes: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41347850490
- Branch de memoria: https://github.com/medeirospablo190-alt/Cafe-na-IA/tree/cafeina-ai-knowledge/ai-core/knowledge
- Importacao da sessao real e leitura GitHub em modo DRY_RUN aprovadas.
- Merge remoto, salvamento real, modelo local carregado, REA e conexao com Roblox **nao foram executados**.
- O workflow manual de escrita continua na branch do PR; nao foi implantado na main nem acionado.

**Pontuacao: P0 10/10 + P1 14/15 + P2 3/15 = 27/100.**

## Entrega de modelo aberto e diario de decisoes — 2026-11-01

- Execucao real Ollama + Qwen2.5 0.5B com dados sintéticos, **aprovada**: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41352808367
- Primeiro teste falhou por rejeicao de uma resposta fora do contrato: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41352541441
- A correcao usou schema JSON de enums. O modelo real passou e escolheu a observacao `watch_state`, mantendo `executable=false`.
- Diario saneado e artefato da inferencia real (retencao de 7 dias): https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41353005800
- Sessao historica com 15 batches → agente deterministico → diario de decisoes, CI aprovada: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41353072322

**Limites:** o Qwen 0.5B e adequado para verificar infraestrutura, mas nao demonstra capacidade para reconstruir jogos complexos. O teste real usou somente fixture sintetica; registros historicos nao foram enviados ao modelo. P1 continua em 14/15 e P3–P8 permanecem em 0.
