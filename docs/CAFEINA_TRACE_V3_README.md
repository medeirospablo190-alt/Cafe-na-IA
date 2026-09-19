# CAFEÍNA Universal Game Trace V3.2.1

Arquivos principais:

- `Cafeina_Universal_Game_Trace_V3_0.lua`: coletor cliente/executor.
- `collector-v3-routes.js`: rotas V3 do gateway.
- `test/collector-v3-routes.test.mjs`: testes de integração da API V3.
- `.github/workflows/cafeina-trace-v3-ci.yml`: validação Node + compilação Luau.

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
- retries mantêm índice/conteúdo estáveis;
- `acknowledgedDataBytes` representa somente bytes realmente confirmados pelo servidor/GitHub;
- cache local preserva cauda não confirmada quando `writefile` está disponível.

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
