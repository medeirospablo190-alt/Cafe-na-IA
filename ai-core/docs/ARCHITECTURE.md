# Arquitetura alvo (ainda não implantada)

```text
Coletor Roblox V3 --HTTPS--> Gateway existente --GitHub--> batches/manifests
                            ^                              |
                            |                              v
                      fila de missoes <--- GitHub Actions + CAFEINA AI Core
                                                   |
                                  +----------------+--------------+
                                  |                |              |
                              REA CLI/MCP      agentes/modelo   Evidence Store
                                  |                |              |
                                  +----------------+--------------+
                                                   |
                                         codigo Luau novo + testes
                                                   |
                                         Pull Request -> revisao
                                                   |
                                         Rojo -> jogo autorizado
```

O gateway existente ja implementa postagem de batches e manifestos V3 e espelhamento por `gameId/placeId/runId`. Não vamos colocá-lo sob responsabilidade dos agentes.

**V0 atual:** somente uma análise local e proposta passiva; não existe canal reverso nem modelo conectado. Evento `remote_outbound` nunca é prova de comportamento interno do servidor.

**Futuro contrato:** `missionId` único, `gameId`, `placeId`, `runId`, tipo e parâmetros da ferramenta, prazo, risco, escopo autorizado, aprovação e estado. Exigir idempotência, limite de uso, logs e cancelamento. Executar apenas ferramentas de allowlist.

**Memória futura:** separar conhecimento EXPERIMENTAL / VALIDATED / CONSOLIDATED / OBSOLETE, armazenar hipóteses com referências, contradições e resultados comparativos. Não transcrever código ou assets protegidos de terceiros.

**Compatibilidade observada em dados reais:** os batches e o manifesto têm `schemaVersion: 3`, enquanto os arquivos em `inventory-traces-v3/profiles/<gameId>.json` atualmente têm `schemaVersion: 1`. O adaptador aceita perfis V1 e V3, sempre validando o `gameId` e publicando apenas contadores permitidos.

## Planejamento offline validado

Tarefas de planejamento distintas de missões do menu são mantidas em `ai-core/src/task-engine.mjs` e têm estados CREATED, RUNNING, WAITING_USER, COMPLETED, FAILED, CANCELLED e EXPIRED. START/FINISH/RECOVER são eventos de **análise de metadados**, jamais comandos para o Roblox. O lease expira, a tarefa pode ser recuperada até o limite de tentativas e todas as revisões são verificadas antes da gravação atômica.

O contrato de especialistas `ai-core/src/specialists.mjs` bloqueia geração de código enquanto a causalidade não tiver sido verificada. REA, publicações, modelos poderosos e ferramentas de execução ainda são integrações futuras.

## Ponte read-only para o REA

A analise offline agora produz `rea-handoff-*.json` com referencias V3 saneadas e questoes pendentes. A origem dessas referencias e CAFEINA e **nao** equivale a um `evidence_id` autenticado do REA. O workflow separado executa o REA 6.7.0 com um ledger vazio, confirmando que o CLI inicia no GitHub Actions sem fabricar obrigacoes. A ligacao com Evidence real, importacao, comparacao e validacao de mecanicas continua pendente.
