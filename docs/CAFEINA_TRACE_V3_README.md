# CAFEÍNA Universal Game Trace V3.1.0

Arquivos principais:

- `Cafeina_Universal_Game_Trace_V3_0.lua`: coletor cliente/executor.
- `collector-v3-routes.js`: rotas V3 do gateway.
- `test/collector-v3-routes.test.mjs`: testes de integração da API V3.
- `.github/workflows/cafeina-trace-v3-ci.yml`: validação Node + compilação Luau.

## O que mudou no V3.1.0

A V3.1 continua sendo um coletor universal. Não há nomes de jogos, remotes, itens, armas, moedas ou mecânicas específicas codificados para uma experiência.

1. **Novidade semântica universal:** além do formato dos argumentos, o coletor cria uma assinatura semântica compacta. Strings, pequenos inteiros, faixas numéricas, enums, instâncias, tabelas e buffers podem revelar um comportamento novo mesmo quando o schema é idêntico.
2. **Memória semântica por GameId:** padrões semânticos aceitos entram em `knownSemanticHashes` e deixam de ser reaprendidos como novidade em toda sessão.
3. **Buffers opacos:** buffers passam a registrar comprimento/faixa, amostra limitada, hash, início/fim em hexadecimal e comparação com a amostra anterior. Não existe decoder específico de jogo.
4. **Retorno de InvokeServer:** quando o executor permite o hook atual, o retorno real é preservado byte a byte na semântica Lua (inclusive múltiplos valores/nils) e registrado junto com schema, sem repetir a chamada.
5. **Lupa automática:** eventos novos/importantes podem abrir até três snapshots curtos do estado cliente depois da ação, com limites e desativação sob pressão.
6. **Correlação por evidência:** `causeCandidates` agora inclui suporte, baseline e confiança. É evidência temporal acumulada, nunca prova de causalidade.
7. **Sequências comportamentais:** transições entre ações/eventos importantes são resumidas por frequência e intervalo.
8. **Ciclo de vida e ruído de runtime:** objetos adicionados/removidos ganham duração quando observável; padrões repetitivos passam a ser amostrados em vez de ocupar o fluxo inteiro.
9. **ValueBase sem ambiguidade:** cada mudança guarda `eventValue` e `observedAfterValue` separadamente.
10. A rota HTTP continua `/api/inventory-trace-v3`, o histórico continua append-only/idempotente e o mesmo arquivo de coletor continua sendo usado.

## Compatibilidade com V3.0.1

As garantias da V3.0.1 abaixo continuam válidas:

1. O coletor continua passivo quanto a ações próprias, mas agora pode observar tráfego nos dois sentidos quando o executor oferece `hookmetamethod` + `getnamecallmethod`.
2. Chamadas reais feitas pelo cliente via `FireServer` e `InvokeServer` são registradas como `remote_outbound` sem alterar os argumentos nem repetir a chamada.
3. Cada chamada outbound recebe assinatura de formato, assinatura exata, esquema dos argumentos e uma pontuação de importância.
4. Remotes de maior interesse abrem automaticamente uma janela curta de investigação aprofundada.
5. Eventos recebidos, mudanças de valores, inventário, objetos e atributos ocorridos logo depois carregam `causeCandidates`. Isso é correlação temporal, não afirmação de causalidade.
6. O formato dos argumentos é inferido apenas de chamadas observadas; o coletor não inventa argumentos.
7. Formatos outbound novos entram na mesma memória persistente de shapes do `GameId`, evitando reaprender a mesma estrutura em toda sessão.
8. O manifesto final contém um bloco `intelligence` com quantidade de outbound observados/aceitos, candidatos de alto interesse, correlações abertas e foco mais importante da sessão.

## Correção herdada do travamento em “ENVIANDO”

A V3.0 original podia enviar lotes muito pequenos porque o loop da UI tentava esvaziar qualquer fila a cada 0,25 s. Em coleta longa isso podia consumir os 179 lotes de dados e deixar o lote final reservado ao manifesto enquanto ainda existiam poucos KB na fila, criando um deadlock.

A correção introduzida na V3.0.1 e preservada na V3.1 funciona em duas camadas:

- durante a coleta, o envio normal espera aproximadamente 70% do alvo de 1,75 MiB ou até 10 s de latência;
- durante a finalização, a fila restante é drenada imediatamente;
- o último slot continua reservado ao manifesto;
- se o orçamento de lotes for atingido mesmo assim, apenas a cauda ainda não enviada é contabilizada como `batch_budget_bytes` e descartada, permitindo que o manifesto seja concluído em vez de ficar preso;
- `acknowledgedDataBytes` não é mais forçado artificialmente para o total coletado, então o manifesto informa corretamente qualquer cauda não confirmada.

Isso também permite que um cache antigo preso no lote 179 seja finalizado na próxima execução: a V3.0.1 preserva os 179 lotes já confirmados e agora ainda possui folga para enviar a cauda pendente antes do manifesto.

## Regras gerais

1. Deduplicação exata por sessão; repetições viram contadores.
2. Memória persistente por `game.GameId`.
3. Um jogo diferente usa perfil independente.
4. Dados estáticos de baixo valor só voltam a ser coletados quando o fingerprint muda.
5. Remotes e payloads novos recebem investigação contextual.
6. Estratégia adaptativa por categoria com amostragem baseada em novidade.
7. Scans incrementais e limitados por tempo para proteger FPS no celular.
8. Backpressure reduz dados menos importantes antes da fila crescer demais.
9. 96 MiB = orçamento suave, 128 MiB = proteção, 150 MiB = teto rígido de coleta.
10. Lotes só são reconhecidos depois que a API confirma o espelho no GitHub.
11. Retry mantém índice e conteúdo estáveis.
12. Histórico é append-only/idempotente por `gameId/placeId/runId/batch`.
13. Perfil só é atualizado pelo manifesto final e não reaplica o mesmo `runId`.
14. Cache local guarda apenas a parte ainda não confirmada quando `writefile` está disponível.
15. UI permanece compacta: MB, porcentagem e um único botão.

## Observação outbound

Quando suportado pelo executor, o coletor instala um único dispatcher de `__namecall` reutilizável entre reinicializações do script. Ele observa somente:

- `RemoteEvent:FireServer(...)`
- `RemoteFunction:InvokeServer(...)`

A chamada original continua pelo `__namecall` original. O CAFEÍNA não muda os argumentos, não cancela a chamada e não dispara uma segunda chamada.

Se o executor não oferecer as funções necessárias, a coleta continua funcionando normalmente e o manifesto registra `outboundObserver = "unavailable"`.

## Integração do servidor

A rota permanece `/api/inventory-trace-v3` e o schema HTTP continua na versão 3, portanto não é necessária migração do backend para aceitar os novos registros.

Variáveis relevantes:

- `AVATAR_DUMP_GITHUB_TOKEN`
- `AVATAR_DUMP_GITHUB_REPO`
- `AVATAR_DUMP_GITHUB_BRANCH`
- `INVENTORY_TRACE_V3_GITHUB_PATH=inventory-traces-v3`
- `INVENTORY_TRACE_V3_MAX_PER_WINDOW=220`
- `INVENTORY_TRACE_V3_WINDOW_SECONDS=600`
- `INVENTORY_TRACE_V3_BODY_LIMIT=3mb`
- `INVENTORY_TRACE_V3_MAX_RECORDS=6000`
- `INVENTORY_TRACE_V3_MAX_REMOTES=1000`
- `INVENTORY_TRACE_V3_MAX_BATCHES=260`
- `INVENTORY_TRACE_V3_PROFILE_SEMANTIC_MAX=12000`

## Estrutura persistente

Histórico:

`inventory-traces-v3/<gameId>/<placeId>/<runId>/<batch>.json`

Manifesto mais recente:

`inventory-traces-v3/<gameId>/<placeId>/latest.json`

Memória compacta do jogo:

`inventory-traces-v3/profiles/<gameId>.json`

## Validação

O workflow `CAFEINA Trace V3 CI`:

- verifica sintaxe Node;
- executa os testes da rota V3;
- baixa o compilador oficial Luau 0.739;
- compila `Cafeina_Universal_Game_Trace_V3_0.lua`.

A validação real final continua sendo uma execução no executor/mobile, porque disponibilidade de hooks de `__namecall` varia por executor.
