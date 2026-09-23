# CAFEÍNA Universal Game Trace V3.2.7

Arquivos principais:

- `Cafeina_Universal_Game_Trace_V3_0.lua`: coletor cliente/executor.
- `collector-v3-routes.js`: rotas V3 do gateway.
- `test/collector-v3-routes.test.mjs`: testes de integração da API V3.
- `.github/workflows/cafeina-trace-v3-ci.yml`: validação Node + compilação Luau.

## V3.2.7 — reenvio durável e diagnóstico automático de upload

A V3.2.7 corrige o cenário observado em produção em que o servidor/GitHub já havia persistido um lote, mas o executor perdeu a resposta de ACK antes de avançar o `batchIndex`. Ao reabrir, versões anteriores reconstruíam esse lote a partir da fila e podiam gerar um corpo diferente, causando `HTTP 409 — lote já existe com conteúdo diferente`.

A correção mantém a coleta intacta e atua somente na camada de transporte/recuperação:

- o corpo JSON exato de cada lote em voo é preservado antes do POST em um arquivo local pequeno de outbox;
- caches novos usam `schemaVersion=4` e, quando existe um lote pendente, guardam também corpo exato, índice, bytes e quantidade de itens;
- um retry após perda de ACK reutiliza o mesmo corpo em vez de reconstruir o lote;
- durante recuperação de cache, o avanço da fila é salvo antes de apagar o outbox, fechando a janela de crash entre ACK e checkpoint;
- o manifesto final também preserva seu corpo exato entre retries;
- erros determinísticos como `409`, `400` e `413` bloqueiam retries cegos; erros transitórios como `429`, falhas de rede e `5xx` continuam elegíveis a retry;
- o menu continua com 232×132 no estado normal; um botão `DIAG` e um painel separado aparecem somente quando existe erro de upload ou anomalia já detectada pelo watchdog;
- o painel mostra versão, run, GameId/PlaceId, batch local/alvo, fila, ACK/total, schema do cache, presença de lote exato, estado de upload/finalização, watchdog e erro HTTP resumido;
- `getgenv().__CAFEINA_UNIVERSAL_TRACE_V30.Diagnostic()` expõe o mesmo estado em formato compacto para diagnóstico externo.

O outbox não aumenta scans, watchers, frequência de coleta, investigação, orçamento de memória da sessão nem limites da API. A escrita adicional ocorre apenas quando um lote realmente vai ser transmitido.

Caches antigos (`schemaVersion=3`) continuam carregando. Se um ACK antigo foi perdido e o mesmo índice já existe no GitHub, o servidor devolve somente metadados seguros do lote existente (índice, bytes, contagens e hashes compactos). O cliente só avança a fila quando o prefixo local coincide nesses campos; caso qualquer verificação falhe, nada é removido, retries determinísticos são bloqueados e o painel mostra o diagnóstico. Essa elegibilidade de recuperação também é preservada se houver outro reinício durante o processo.

## V3.2.6 — qualidade causal e contexto das investigações

A V3.2.6 melhora a interpretação dos dados sem aumentar scans ou frequência de coleta:

- correlações passam a carregar `relationStage`: `candidate`, `repeated`, `confirmed` ou `weak_context`;
- objetos criados/removidos dentro de personagens de jogadores recebem peso causal menor (exceto `Tool`), reduzindo associações acidentais com churn de avatar;
- confiança causal considera suporte confiável, baseline, proximidade temporal e consistência do intervalo;
- `confirmed` exige pelo menos duas ocorrências distintas do efeito, evitando que várias janelas contem o mesmo evento como confirmações separadas;
- `remoteImpact` só sobe por correlação quando há pelo menos 3 suportes, 2 suportes confiáveis e confiança mínima;
- relações confirmadas deixam de consumir novas investigações repetidas na mesma sessão;
- cada candidato guarda `queuedAt`, contexto compacto ao entrar na fila e hashes de contexto no início/antes do teste;
- bundles registram se as condições mudaram entre detecção e teste;
- resultados repetidos da mesma investigação passam a indicar `outcomeStage=confirmed` no delta da sessão;
- watchdog mede a idade real do candidato mais antigo antes de declarar fila parada.

Não foram alterados hook outbound v4, scans, frequência, snapshots, limites de memória/upload, API ou os gates existentes de replay.

## V3.2.5 — watchdog após o worker da fila

A V3.2.5 corrige apenas o falso positivo `queue_waiting_without_active` observado na primeira sessão da V3.2.4. No loop já existente, o worker da fila passa a rodar **antes** da checagem do watchdog. Assim, um candidato recém-enfileirado pode iniciar normalmente no mesmo ciclo antes de ser classificado como fila parada.

Não foram alterados hook outbound v4, lógica das investigações, testes ativos/passivos, scans, snapshots, limites, API, frequência do loop nem orçamento de memória.

## V3.2.4 — fila segura e autodiagnóstico leve

A V3.2.4 corrige a causa localizada pela V3.2.3 sem alterar o hook outbound v4: o callback derivado do observer **não inicia mais diretamente a investigação/UI**. Ele apenas valida e enfileira o candidato. O início real da investigação acontece no loop normal do menu, fora do contexto derivado do hook, evitando que `setInputQuarantine`/GUI herdem uma capability inadequada.

O autodiagnóstico foi adicionado como uma camada separada e limitada:

- reutiliza o loop já existente de 0,25 s; a checagem de saúde só roda a cada 1,5 s;
- mantém no máximo 160 eventos compactos em memória;
- registra mudanças de estado/etapa sem fazer upload de cada mudança;
- envia `menu_health_diag` apenas quando encontra uma anomalia/erro novo;
- observa consistência entre investigação ativa, cor, etapa, fila e quarentena de input;
- detecta YELLOW/RED/BLUE presos além das janelas esperadas;
- protege o refresh visual com `pcall` e guarda traceback quando disponível;
- inclui uma cauda curta do diagnóstico no `investigation_bundle` e no manifesto final;
- não faz autocorreção silenciosa de estado, para não esconder a causa de um problema.

Não foram alterados: hook outbound v4, scans, frequência de scans, snapshots, limites de upload, orçamento de memória, gates de risco dos testes ativos ou formato da API.

## Diagnóstico fino da V3.2.3

A V3.2.3 estreita o diagnóstico para a transição que acontece logo depois de definir o estado YELLOW e antes de agendar o timer amarelo.

Durante essa transição, o bundle mantém em memória os seguintes marcos:

- `yellow_state_set`
- `yellow_before_quarantine`
- `yellow_after_quarantine`
- `yellow_before_ui_defer`
- `yellow_after_ui_defer`
- `yellow_quarantine_error`
- `yellow_ui_defer_error`
- `yellow_ui_missing`

Esses micro-marcadores não entram imediatamente na fila de upload, para não interferirem no trecho que está sendo diagnosticado. Eles ficam no array limitado de diagnósticos da investigação e aparecem no `investigation_bundle` quando a investigação termina ou é cancelada.

A chamada inicial de `setInvestigatorState("YELLOW")` agora é protegida por `pcall`. Se ela falhar, o coletor grava `yellow_state_transition` como origem do erro e não agenda o timer como se a transição tivesse sido concluída.

Erros de `setInputQuarantine` e do agendamento de atualização da UI são registrados separadamente e relançados, preservando o comportamento original em vez de mascarar a falha.

O menu também conhece os novos estados intermediários, por exemplo `AMARELO • ANTES INPUT`, `AMARELO • INPUT OK`, `AMARELO • ANTES UI` e `AMARELO • UI AGENDADA`.

## Diagnóstico da V3.2.2

A V3.2.2 não tenta corrigir automaticamente o caso de uma investigação permanecer em AMARELO. Ela adiciona rastreabilidade suficiente para descobrir a causa sem hipótese.

O menu compacto passa a mostrar a etapa interna atual junto da cor, por exemplo:

- `AMARELO • TIMER AGENDADO`
- `AMARELO • TIMER DISPAROU`
- `AMARELO • EXECUTANDO`
- `AMARELO • RISCO OK`
- `AMARELO • ESTABILIDADE`
- `AMARELO • AGUARDANDO ESTAB.`
- `VERMELHO • EXECUTANDO AÇÃO`
- `AZUL • OBSERVANDO`
- `AMARELO • ERRO INTERNO`

Enquanto a investigação está ativa, o menu também mostra há quanto tempo a etapa atual está ativa.

Cada troca relevante de etapa gera um registro pequeno `investigator_diag` contendo:

- ID da investigação;
- etapa e detalhe;
- estado de cor;
- modo;
- pressão atual;
- frame time médio;
- Remote relacionado.

O `investigation_bundle` final mantém uma lista limitada desses diagnósticos. O manifesto também inclui a última etapa, último erro, total de marcadores e total de erros.

Os callbacks do primeiro timer amarelo e dos retries de estabilidade agora executam `executeCandidate` dentro de `pcall`. Se houver uma exceção antes da mudança de estado, ela é registrada como `execute_error` em vez de desaparecer sem evidência.

O limite é de 40 marcadores por investigação. Não foram aumentados caps de scan, frequência de coleta, tamanho de snapshot ou orçamento de upload.

## Ajustes da V3.2.1

A V3.2.1 faz três ajustes de qualidade observados em coleta real, sem aumentar os caps de scan, frequência de coleta ou tamanho máximo de sessão:

1. **Contexto direto também pode abrir investigação:** um `FireServer` observado logo após `GuiButton.Activated`, `Tool.Activated` ou `ProximityPrompt.Triggered` pode entrar na fila mesmo quando shape e semântica do Remote já são conhecidos. O contexto precisa estar dentro de uma janela curta e o teste ativo continua passando pelos mesmos filtros genéricos de risco.
2. **Player normalizado na assinatura semântica:** argumentos `Instance` de classe `Player` usam `I:Player` na assinatura de novidade. O payload armazenado continua contendo a instância/nome real; somente a decisão de novidade deixa de reaprender a mesma mecânica para cada jogador diferente.
3. **Values de background não dominam a lupa:** a coleta normal de `ValueBase` não muda, mas snapshots profundos priorizam paths pouco repetitivos e limitam a quatro as entradas de paths já muito ativos. O buffer total continua em 32 e o snapshot em até 16 valores.

## Objetivo da V3.2

A V3.2 mantém o CAFEÍNA universal: não contém nomes de jogos, remotes, itens, moedas ou mecânicas específicas de uma experiência.

A evolução principal é o **Investigador Adaptativo**. O coletor continua observando tudo que a V3.1 já observava e, quando encontra uma ação nova/importante, cria uma investigação delimitada com contexto anterior, estado antes/depois, consequências observadas e um pacote final único.

A observação outbound continua sem alterar chamadas reais do jogo. O modo ativo é separado: ele só considera repetir um `RemoteEvent:FireServer` que já foi observado naturalmente, com os mesmos argumentos clonáveis e depois de filtros genéricos de risco. Ele não inventa remotes/argumentos, não repete `InvokeServer` e não testa automaticamente uma ação quando houver evidência de efeitos persistentes ou alto impacto.

## Estados da investigação e interface

A UI continua compacta e pode ser minimizada em um ícone flutuante e arrastável. O ícone e a faixa do menu usam a mesma máquina de estados:

- **VERDE — LIVRE:** coleta normal; o jogador pode jogar normalmente.
- **AMARELO — AVISO:** foi encontrada uma investigação candidata. É apenas aviso para parar de mexer; o input ainda não é bloqueado.
- **VERMELHO — TESTE AUTOMÁTICO:** uma interação controlada está sendo executada. O input do jogador é temporariamente colocado em quarentena.
- **AZUL — OBSERVANDO:** nenhuma nova interação é gerada; o coletor mede as consequências enquanto a quarentena continua ativa.

Durante VERMELHO/AZUL o painel minimiza automaticamente, deixando o ícone do CAFEÍNA acima da barreira de input. Tocar nesse ícone encerra a investigação atual, libera o input e reabre o painel.

A quarentena usa `ContextActionService` para movimento/pulo/controles e uma camada transparente da própria UI para impedir toques acidentais no jogo. Ela não altera `Humanoid`, `Camera`, `WalkSpeed`, `JumpPower` ou a posição do personagem. Finalização, Stop, destruição da GUI e restauração de cache sempre liberam a quarentena.

## Investigador Adaptativo

Uma ação candidata passa pelas seguintes etapas:

1. a ocorrência natural é observada e registrada normalmente;
2. o CAFEÍNA guarda os segundos anteriores em um buffer circular;
3. entra em AMARELO e espera o personagem/cliente estabilizar;
4. avalia genericamente se a ação pode ser repetida;
5. se for elegível, entra em VERMELHO e repete uma única vez o `FireServer` já observado;
6. entra em AZUL e acompanha as consequências;
7. produz um `investigation_bundle`;
8. volta a VERDE e segue para a próxima investigação da fila.

O teste ativo é limitado por sessão, cooldown por padrão e fila máxima. Pressão de FPS/fila desativa aprofundamento ativo.

Ações são convertidas para modo somente observacional quando, entre outros casos:

- não são `FireServer` de um `RemoteEvent`;
- os argumentos não podem ser clonados de forma conservadora;
- o score de impacto está alto;
- a ação já mostrou alteração persistente de Value/Tool/Attribute/Character;
- o perfil do jogo já possui testes suficientes daquele padrão;
- o cliente está sob pressão ou o personagem não estabiliza.

## Action Bundle e state diff

Cada investigação concluída registra um pacote único com:

- candidato e hashes de shape/semântica;
- prelude dos segundos anteriores;
- estado quando a ação foi detectada;
- estado imediatamente antes do teste;
- snapshot intermediário;
- estado final;
- eventos relevantes da janela;
- execução do teste, quando houve;
- diferença compacta antes/depois;
- score de impacto observado.

O diff destaca mudanças de atributos, ferramentas, valores, GUI, health/state e deslocamento, em vez de depender apenas de snapshots completos.

## Contexto de interação

A V3.2 amplia os marcadores que ajudam a explicar o que originou uma ação:

- `ProximityPrompt`: shown, hidden e triggered;
- `Tool`: added/removed, equipped, unequipped e activated;
- GUI: `GuiButton.Activated`, mudanças de `Visible` e `ScreenGui.Enabled`;
- remotes inbound/outbound;
- Values e Attributes;
- objetos criados/removidos;
- personagem e trajetória.

A instrumentação de PlayerGui é incremental e limitada pelo mesmo orçamento de nós da varredura de GUI, evitando um `GetDescendants()` ilimitado no início da sessão.

## Normalização de ruído

Fingerprints de runtime, estrutura, objetos estáticos e partes próximas agora podem usar caminhos normalizados.

Quando um objeto pertence a um Character real de jogador, o topo é representado estruturalmente como `Workspace.<Character>`. Segmentos claramente dinâmicos/numéricos também são compactados antes da decisão de novidade.

Isso reduz o caso em que a mesma estrutura de avatar de dezenas de jogadores era aprendida como milhares de novidades diferentes, sem remover o caminho real dos registros que forem efetivamente armazenados.

## Evolução de protocolo e campos

Além de shape e semântica, a sessão mantém modelos compactos por fluxo:

- quantidade de observações;
- mudanças de shape;
- mudanças semânticas;
- quantidade de shapes/semânticas distintas.

Campos de argumentos/tabelas também recebem estatísticas de estabilidade: número de observações, mudanças e tipos encontrados. O manifesto resume os campos mais variáveis para facilitar descobrir seletores, modos, quantidades e outros discriminantes sem codificar conhecimento de um jogo.

## Buffers opacos

A análise genérica de buffers da V3.1 continua ativa e agora preserva também a amostra hexadecimal limitada usada no fingerprint. Quando existe uma amostra anterior do mesmo fluxo/posição, o coletor calcula quanto da amostra mudou.

Não existe decoder específico de protocolo.

## Memória entre sessões

O perfil por `game.GameId` continua guardando:

- hashes estáticos/low-value;
- shapes;
- semânticas;
- remotes;
- frontier;
- estratégia adaptativa.

A V3.2 acrescenta `investigationKnowledge`, uma lista limitada de padrões investigados, incluindo contadores de observações, testes ativos, conclusões, casos somente passivos/cancelados e o último impacto/resultado.

Assim uma nova sessão não precisa tratar como desconhecido um comportamento já suficientemente investigado.

## Garantias herdadas da V3.1

Continuam válidos:

1. novidade semântica independente de shape;
2. memória semântica por GameId;
3. fingerprint genérico de buffers;
4. captura do retorno real de `InvokeServer` sem executar uma segunda chamada;
5. lupa automática com snapshots limitados;
6. correlação com suporte, baseline e confiança;
7. grafo compacto de transições comportamentais;
8. ciclo de vida e amostragem de runtime;
9. `eventValue` e `observedAfterValue` separados para ValueBase;
10. backpressure, limites de memória e streaming protegido.

## Hook outbound

O dispatcher de `__namecall` continua reutilizável entre reinicializações.

Para chamadas naturais:

- `RemoteEvent:FireServer(...)` é observado sem mudar argumentos ou bloquear o encaminhamento original;
- `RemoteFunction:InvokeServer(...)` executa a chamada original uma vez, preserva múltiplos retornos/nils e só então agenda a análise.

A V3.2 adiciona um token interno somente durante um teste automático para distinguir a repetição controlada da ocorrência natural. A repetição nunca volta para a fila como uma nova investigação.

Se o executor não oferecer os hooks necessários, o restante da coleta continua e `outboundObserver` registra a indisponibilidade.

## Streaming e finalização

A correção contra travamento em **ENVIANDO** permanece intacta:

- durante coleta normal, batches esperam o alvo mínimo ou latência máxima;
- finalização drena a fila restante;
- sempre fica reservado um slot para o manifesto;
- retries mantêm índice e corpo exato estáveis por meio do outbox durável;
- `acknowledgedDataBytes` representa somente bytes realmente confirmados pelo servidor/GitHub;
- cache local preserva cauda não confirmada quando `writefile` está disponível;
- perda de ACK não força reconstrução do lote já persistido;
- conflitos determinísticos param em estado diagnosticável em vez de repetir indefinidamente.

Limites principais continuam:

- 96 MiB: orçamento suave;
- 128 MiB: proteção;
- 150 MiB: teto rígido;
- máximo de 260 batches.

## Integração do servidor

A rota permanece:

`/api/inventory-trace-v3`

e o schema HTTP continua em 3. Não é necessária migração de URL.

Variáveis relevantes:

- `CAFEINA_COLLECTOR_GITHUB_TOKEN`
- `CAFEINA_COLLECTOR_GITHUB_REPO`
- `CAFEINA_COLLECTOR_GITHUB_BRANCH`
- `INVENTORY_TRACE_V3_GITHUB_PATH=inventory-traces-v3`
- `INVENTORY_TRACE_V3_MAX_PER_WINDOW=220`
- `INVENTORY_TRACE_V3_WINDOW_SECONDS=600`
- `INVENTORY_TRACE_V3_BODY_LIMIT=3mb`
- `INVENTORY_TRACE_V3_MAX_RECORDS=6000`
- `INVENTORY_TRACE_V3_MAX_REMOTES=1000`
- `INVENTORY_TRACE_V3_MAX_BATCHES=260`
- `INVENTORY_TRACE_V3_PROFILE_SEMANTIC_MAX=12000`
- `INVENTORY_TRACE_V3_PROFILE_INVESTIGATION_MAX=800`

O health expõe o limite de `investigationKnowledge` dentro de `profileCaps`.

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
- baixa o compilador oficial Luau;
- compila `Cafeina_Universal_Game_Trace_V3_0.lua`.

Além do CI, a validação final precisa de uma execução real no executor/mobile, porque disponibilidade/comportamento de `hookmetamethod`, `ContextActionService` e camadas de input podem variar conforme o executor e o cliente Roblox.
