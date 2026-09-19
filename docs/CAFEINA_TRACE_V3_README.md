# CAFEÍNA Universal Game Trace V3.0

Arquivos:

- `Cafeina_Universal_Game_Trace_V3_0.lua`: coletor cliente/executor.
- `collector-v3-routes.js`: rotas V3 do gateway, separadas da API V2.1.
- `test/collector-v3-routes.test.mjs`: testes de integração da API V3.
- `.github/workflows/cafeina-trace-v3-ci.yml`: validação Node + compilação do Luau.

## Regras implementadas

1. Coleta passiva: não dispara remotes desconhecidos.
2. Deduplicação por assinatura exata durante a sessão; repetições viram contadores em vez de cópias completas.
3. Memória persistente por `game.GameId`, carregada antes da coleta.
4. Um jogo diferente começa com perfil independente; voltar ao mesmo jogo reutiliza o perfil conhecido.
5. Dados estáticos/baixo valor usam fingerprints de estado: se nada mudou, não são coletados novamente; se o estado realmente mudou, voltam a ser novidade.
6. Remotes e formatos de payload novos recebem uma janela curta de investigação aprofundada e um snapshot contextual do sistema ao redor.
7. Estratégia adaptativa por categoria, com amostragem baseada na taxa real de novidade; o código não se auto-modifica.
8. Correlação leve por `corr` e referências recentes, sem buffer de replay.
9. Motor de cobertura/lacunas: scans limitados registram fronteiras não visitadas e priorizam essas áreas em sessões futuras do mesmo jogo.
10. Varredura incremental em fatias de tempo para não monopolizar frames no celular.
11. Backpressure por fila, FPS e orçamento total; dados de menor prioridade são reduzidos primeiro.
12. Streaming para o servidor em lotes de ~1,75 MiB; o cliente não precisa manter 150 MB na RAM.
13. Orçamento total: 96 MiB normal, 128 MiB proteção, 150 MiB teto rígido.
14. O lote só é reconhecido no cliente quando a API confirma que o GitHub possui exatamente aquele lote.
15. Retry é realmente idempotente: índice, `capturedAt` e manifesto ficam estáveis até a confirmação; uma resposta perdida não muda o conteúdo do retry.
16. Lotes usam caminho determinístico por `gameId/placeId/runId/batch`, permitindo retry idempotente e detectando conflito de conteúdo.
17. O perfil do jogo é atualizado apenas no manifesto final e protegido contra reaplicação do mesmo `runId`.
18. Cache local guarda apenas dados ainda não confirmados quando o executor oferece `writefile`; sem `writefile`, o retry continua disponível em memória enquanto a sessão existir.
19. UI compacta: MB coletados, porcentagem confirmada e um único botão.
20. UI usa `CoreUISafeInsets`, uma raiz de área segura, drag só pelo cabeçalho e posição limitada à área utilizável do celular.
21. Nenhum replay detalhado e nenhum painel explicador/verboso.

## Integração do servidor

1. `collector-v3-routes.js` fica na raiz ao lado de `gateway-main.js`.
2. `gateway-main.js` importa e instala `installCollectorV3Routes(app)`.
3. O módulo reutiliza as variáveis já existentes do GitHub:
   - `AVATAR_DUMP_GITHUB_TOKEN`
   - `AVATAR_DUMP_GITHUB_REPO`
   - `AVATAR_DUMP_GITHUB_BRANCH`
4. Opcionalmente configure:
   - `INVENTORY_TRACE_V3_GITHUB_PATH=inventory-traces-v3`
   - `INVENTORY_TRACE_V3_MAX_PER_WINDOW=220`
   - `INVENTORY_TRACE_V3_WINDOW_SECONDS=600`
   - `INVENTORY_TRACE_V3_BODY_LIMIT=3mb`
   - `INVENTORY_TRACE_V3_MAX_RECORDS=6000`
   - `INVENTORY_TRACE_V3_MAX_REMOTES=1000`
   - `INVENTORY_TRACE_V3_MAX_BATCHES=180`
5. A leitura de arquivos de lote no GitHub usa o media type `raw`, necessário para arquivos entre 1 e 100 MB; isso mantém a detecção de conflito funcionando mesmo com lotes acima de 1 MB.
6. Faça deploy e confirme `/api/inventory-trace-v3/health` com `githubMirrorConfigured: true`.
7. Só então execute o Lua V3.

## Estrutura persistente

Histórico append-only/idempotente:

`inventory-traces-v3/<gameId>/<placeId>/<runId>/<batch>.json`

Manifesto mais recente:

`inventory-traces-v3/<gameId>/<placeId>/latest.json`

Memória compacta por jogo:

`inventory-traces-v3/profiles/<gameId>.json`

Assim o cliente não precisa reler o histórico bruto. Ele baixa apenas a memória compacta do mesmo `GameId` e envia somente novidade útil/estado novo.

## Validação feita antes da entrega

- `collector-v3-routes.js`: `node --check` aprovado.
- `test/collector-v3-routes.test.mjs`: teste de idempotência, conflito, perfil e leitura raw de lote acima de 1 MB.
- Teste local com GitHub simulado: lote inicial `201`, retry idêntico `201`, conflito do mesmo lote `409`, manifesto `201`, retry de manifesto idempotente e perfil aplicado uma única vez.
- O coletor Lua passou por checagem lexical/estrutural local. O workflow `CAFEINA Trace V3 CI` baixa o compilador oficial Luau 0.739 e compila o arquivo antes do merge; depois do deploy, a validação final ainda inclui uma execução real no executor/mobile.

## Importante

A V3 foi desenhada para coexistir com a rota V2.1 (`/api/inventory-trace`). A nova rota usa `/api/inventory-trace-v3`, então o coletor antigo continua disponível durante a transição.