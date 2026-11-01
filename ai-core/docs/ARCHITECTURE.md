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
