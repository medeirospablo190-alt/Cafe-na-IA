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

- **P0 = 7/10**: estrutura, contratos e documentos. Faltam 3 pontos até confirmar CI no GitHub.
- **P1 = 5/15**: leitura de um lote e manifesto V3, checksums, referências e proposta de observação. Faltam múltiplas sessões, perfis e memória real.
- **Demais etapas = 0**: apenas planejadas.

**Inicial: 12/100; faltam 88 pontos.** Registrar links de CI/PR antes de creditar novos pontos.

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
