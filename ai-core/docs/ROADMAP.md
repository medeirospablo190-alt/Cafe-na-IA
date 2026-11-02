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
- **P2 = 13/15**: modelo Qwen2.5 0.5B validado no Actions, agentes, planejamento offline e estado sintético persistido e recuperado por dois runners independentes; integração de persistência no orquestrador completo e qualidade das IAs ainda pendentes.
- **P5 = 3/10**: CLI do REA executada em runner e handoff conservador de evidências V3 testado. Ainda falta Evidence autentica, REA MCP e testes comparativos.
- **P3 = 12/15**: fila e recibos reais GitHub com três runners, verificação de segredo/JOB autorizados em ambiente simulado e check-in HTTP de loopback integrado a token HMAC; experiência Roblox, registro confiável real e Render permanecem pendentes.
- **P4 = 8/15**: ferramentas e autorizações sintéticas, persistência no GitHub e tela de revisão HTTP local com formulário funcional. Não existe interface Roblox, operador real nem execução de ferramentas.
- **P6, P7 e P8 = 0**: ainda não implementadas.

**Atual: 60/100; faltam 40 pontos.** Registrar links de CI/PR antes de creditar novos pontos.

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

## Implementacao de estados de tarefa e especialistas — 2026-11-01

- Contrato local de tarefa `OFFLINE_METADATA_ONLY`: CREATED, RUNNING, WAITING_USER, COMPLETED, FAILED, CANCELLED e EXPIRED; lease, revisoes e tentativas limitadas.
- `src/task-engine.mjs` grava em disco com lock, verifica transicoes e recusa adulteracao de campos ou conclusoes sem identidade e evidencias correspondentes.
- `src/specialists.mjs`: papeis Arquiteta, Programadora e Testadora **deterministicos**, que produzem planos de verificacao, nao Luau nem acoes reais.
- Teste de integracao com uma sessao V3 historica, CI do PR aprovada: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41354703167
- **Limitacao de persistencia:** arquivo de estado sobrevive a reinicio do processo com o mesmo disco, mas nao entre runners descartaveis. `cafeina-ai-knowledge` nao foi usada para gravar tarefas reais.
- Nao houve comunicacao de volta ao Roblox, execucao de REA, modificacao do gateway ou uso de credenciais do jogo.

**Pontuacao atual: P0 10/10 + P1 14/15 + P2 11/15 + P3–P8 0 = 35/100 pontos.**

## Memoria entre runners e REA CLI — 2026-11-01

- GitHub Actions concluiu escrita e leitura da MESMA tarefa **sintetica** em runners independentes usando `cafeina-ai-knowledge` com autenticação e controle de revisão: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41362546343
- REA 6.7.0 iniciou no GitHub Actions com ledger vazio documentado e sem evidência Roblox fictícia: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41362281164
- Pipeline de sessão V3 histórica agora emite `rea-handoff-*.json` com referencias CAFEINA e `reaEvidenceAuthenticated=false`; aprovado pela CI: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41362629393
- **Não foi testado ainda**: execução do REA sobre Evidence real autorizada, integração com o Roblox/gateway, código Luau gerado por agentes ou publicação de testes Roblox.
- A branch de memória tem apenas tarefa de teste sintética; dados brutos de jogadores não foram gravados nesse processo.

**Pontuação atual: P0 10 + P1 14 + P2 13 + P3 0 + P4 0 + P5 3 + P6 0 + P7 0 + P8 0 = 40/100.**

## Primeira camada de comunicacao com o menu — 2026-11-01

- Propostas de missao somente para ferramentas de observacao e nunca executaveis; referencias validadas contra relatorio V3 saneado.
- Recibos de menu limitados a RECEIVED, DECLINED e NOT_EXECUTED; nenhuma dessas mensagens concede aprovacao.
- Gateway HTTP somente no loopback simula polling, ACK e resultado; autenticação com token de **teste**, escopo de sessao, timeout, repeticao idempotente e limite de polling.
- Fila GitHub de propostas imutaveis implementada com `dryRun=true` por padrão; **testada apenas com API simulada**, sem gravacao real de propostas.
- Teste de ponta a ponta **sintetico e simulado** entre a fila e o menu passou no CI: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41363961534
- Documentacao tecnica: `ai-core/docs/MENU_BRIDGE.md`.
- **Nao implementado:** sessao real Roblox autenticada, endpoint de gateway no Render, ACK duravel no GitHub, coletor recebendo novas instrucoes, executores ou aprovacao real de missoes.

**Pontuacao P3 = 3/15; total = 43/100; restam 57 pontos.**

## Resiliencia dos recibos do menu — 2026-11-01

- `src/menu-delivery-state.mjs`: estados QUEUED, DELIVERED, ACKNOWLEDGED e CLOSED_NO_EXECUTION, com transicoes estritas, revisao e horarios limitados.
- `src/github-menu-receipts.mjs`: contrato de armazenamento na branch de conhecimento, exclusivamente para metadados, com leitura e validacao, atualizacao otimista por SHA, retries limitados e dry-run como padrao.
- O simulador do gateway aceita callback opcional de persistencia; em falha da API, responde HTTP 503, sem fingir sucesso.
- Testes E2E usaram HTTP local e **API GitHub simulada**, abrangendo recuperacao dos recibos, idempotencia, conflitos e indisponibilidade.
- [CI do PR aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41364586743) inclui etapa "Check simulated versioned menu receipt resilience".
- **Nao confirmado:** gravacao real de recibos no GitHub, novo endpoint em Render, autenticacao da sessao Roblox, menu real e execucao de ferramentas.

**Pontuacao atual: P3 5/15; total 45/100; faltam 55 pontos.**

## Validação real da fila e de recibos no GitHub — 2026-11-01

- Runner 1 publicou proposta de observação **sintética** na branch `cafeina-ai-knowledge` usando GitHub Contents API, sem dados de jogadores.
- Runner 2 recuperou a proposta pelo GitHub, iniciou gateway **simulado** HTTP em 127.0.0.1, recebeu polling e os recibos RECEIVED / NOT_EXECUTED, e só respondeu após gravar DELIVERED / ACKNOWLEDGED / CLOSED_NO_EXECUTION na API real.
- Runner 3, isolado e com permissão `contents: read`, confirmou `revision=3`, `outcome=NOT_EXECUTED`, `approved=false`, `executed=false`.
- [Primeiro teste de persistência real, três runners](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365030921).
- [Teste HTTP loopback → GitHub real → terceiro runner](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365207503).
- [CI core aprovada (push e PR)](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365211848).
- Os arquivos publicados foram inspecionados via GitHub: apenas gameId=101, placeId=202 e runId sintetico, sem TEST_SECRET, nome de jogador, player IDs ou argumentos brutos.
- **Limitações:** o cliente ainda é um simulador, a autenticação do menu é apenas token efêmero de teste, o gateway real/Render e o coletor continuam inalterados, e não há sistema automático de expurgo de registros antigos.
- O GitHub é armazenamento durável e executor eventual; não é servidor permanente de mensagens em tempo real.

**Pontuação atual: P3 8/15, total 48/100, faltam 52 pontos.**

## Credenciais de sessão e retenção — 2026-11-01

- `src/menu-session-auth.mjs`: protótipo de credencial temporária HMAC-SHA256 vinculada a missão, SHA da proposta, gameId, placeId, runId, prazo de até 5 minutos e escopos limitados a READ_PROPOSAL / SEND_NON_EXECUTION_RECEIPT.
- A emissão depende de `validateTrustedServerSession` que foi **simulada nos testes**. O módulo não contém um verificador de identidade/autorização Roblox e não pode ser implantado sozinho.
- O gateway HTTP de loopback aceita o novo verificador de credencial e bloqueia tokens adulterados, expirados ou referentes a outra proposta. Nem token nem verificador autorizam execução Roblox.
- `src/menu-retention.mjs`: classificação e leitura segura da pasta de propostas **sintéticas** no GitHub, sem implementação de DELETE, PUT ou POST.
- Scan read-only [aprovado no GitHub Actions](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365933661): `scanned=2`, `eligible=0`, `notYetEligible=2`, `deleted=0`.
- Testes de segurança, retenção e fluxo HTTP [CI push](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41366008560) e [CI PR](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41366012830) aprovados.
- **Falta:** atestação confiável de servidor de experiência Roblox, autenticação de conexões reais, HTTPS, mecanismo durável de revogação/replay e interface do menu.

**Pontuação oficial: 50/100. P3 = 10/15. Faltam 50 pontos.**

## Contrato de check-in de servidor Roblox e transporte — 2026-11-01

- `src/roblox-server-verifier.mjs` valida segredo de experiência por `x-api-key`, jogo/place, JobId, missão, relógio e nonce. A função `resolveTrustedJob` **não** está integrada a uma fonte Roblox/servidor real; os testes usam registro sintético. `claimNonce` precisa ser atômico entre servidores em produção.
- `roblox-reference/ServerBridgeReference.server.luau` é um exemplo **desativado** de `ServerScriptService` usando `HttpService:GetSecret` e `HttpService:RequestAsync`, sem URL real e sem instalar no jogo.
- `src/roblox-checkin-sim.mjs` testa POST HTTP local do servidor simulado até a emissão de um token temporário, depois entrega ao menu simulado com ACK e NOT_EXECUTED, sem execução de ferramentas.
- [CI push aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41370030216) e [CI PR aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41370033637).
- Documentação do contrato, limites e fontes oficiais: `docs/ROBLOX_SERVER_BRIDGE.md`.
- **Ainda não existe autenticação Roblox real** nem deployment de gateway, Render, menu, coletor, jogo ou segredos. Nenhuma credencial de produção foi usada.

**Pontuação atual P3 = 12/15; total = 52/100; faltam 48 pontos.**

## Primeira camada do Tool System do coletor — 2026-11-02

- `src/collector-tool-sandbox.mjs` estabelece um catálogo fechado para `watch_state` e `observe_gui`, com privilégio `OFFLINE_METADATA_ONLY`. Este código **não implementa observação real do Roblox**.
- A simulação valida proposta, identidade do jogo, manifesto, evidências do relatório V3, prazo e verificador de fixture sintética, sem tratar ACK do menu como aprovação real.
- Cada sessão permite até 2 prévias de 10 segundos de orçamento (não 10 segundos de coleta real); tentativas repetidas são idempotentes e tentativas simultâneas são rejeitadas.
- `dispatchLiveTool()` sempre lança `LIVE_COLLECTOR_EXECUTION_DISABLED`. Nenhum serviço ou remote é chamado.
- O retorno inclui contagens limitadas e referências de evidências, sem conteúdo bruto, IDs/nome de jogadores ou argumentos. Auditoria lista somente os IDs das tentativas e orçamentos.
- `src/collector-sandbox-demo.mjs` e CI validam duas ferramentas em fixtures sintéticas, sem dados de jogadores: [push aprovado](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41382183465) e [PR aprovado](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41382188608).
- Documentação detalhada: `docs/COLLECTOR_TOOL_SYSTEM.md`.
- **Não implementado:** conexão à coleta real, UI de aprovação, sensor Luau, agendamento do coletor, execução de comandos ou testes ativos autorizados.

**P4 = 3/15. Pontuação do projeto = 55/100; faltam 45 pontos.**

## Solicitação e revisão de permissão somente sintética — 2026-11-02

- `src/collector-permissions.mjs` adiciona pedidos com `PENDING_REVIEW`, motivo de enum, hash da proposta, prazo e privilégio exclusivo de `SYNTHETIC_PREVIEW_ONLY`.
- A função de revisão exige callback de operador **de fixture**, separado dos ACKs do menu. Os únicos resultados são `DENIED` ou `SIMULATION_ALLOWED`, ambos com `authorizedLiveExecution=false`.
- Nova verificação de registro de revisão sintético a cada simulação, incluindo tentativas repetidas. A recusa, expiração, JSON alterado e falta de registro confiável não liberam prévia.
- `src/collector-permissions-demo.mjs` percorre pedido → revisão → prévia → auditoria para `watch_state` e `observe_gui`, sem nenhuma execução real.
- [CI push aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41385453948) e [CI PR aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41385457825).
- Documentação de segurança: `docs/COLLECTOR_PERMISSIONS.md`.
- **Não implementado:** consentimento real, login/autenticação de usuário, execução em Roblox, ligação com coletor/gateway de produção, ou auditoria distribuída/persistente.

**Pontuação P4 = 5/15; total = 57/100; faltam 43 pontos.**

## Permissões sintéticas persistentes e visualização futura — 2026-11-02

- `src/github-collector-permissions.mjs` implementa documento por missão com revisões 0 e 1, controle SHA, escrita opt-in, checagem integral do conteúdo, idempotência e bloqueio de decisões contraditórias.
- Runner 1 gravou um pedido sintético `PENDING_REVIEW`; runner 2 registrou `DENIED` usando **operador fictício de teste**; runner 3 verificou a revisão final com apenas `contents:read`: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41386181653
- Inspeção direta do documento remoto confirmou `revision=1`, `outcome=DENIED`, `liveExecutionRequested=false`, `authorizedLiveExecution=false`, `robloxConnected=false` e identidade `101/202/synthetic-...`, sem campos brutos de jogadores.
- `src/collector-permission-view.mjs` projeta para a futura UI uma representação **somente leitura** da finalidade, limite, prazo e estado. As opções de revisão são apenas rótulos visuais sintéticos, sem função de execução.
- [CI push aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41386415402) e [CI PR aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41386420698).
- Documentação e riscos: `docs/COLLECTOR_PERMISSION_STORAGE.md`.
- **Não implementado:** autenticação de usuário/proprietário real, interface Roblox, consentimento real, revogação distribuída, execução no coletor ou encaminhamento de ferramentas ao gateway.

**Pontuação P4=7/15. Total=59/100; faltam 41 pontos.**

## Interface local funcional de revisão do coletor — 2026-11-02

- `src/collector-review-browser.mjs` oferece uma página de navegador real, servida exclusivamente por HTTP em `127.0.0.1`, com ferramenta, escopo, prazo, orçamento e botões de recusa ou liberação **somente da prévia sintética**.
- O formulário não usa JavaScript externo, nenhuma rota de coletor ou GitHub; verifica Host/Origin, CSRF, corpo de no máximo 512 bytes, estado final único e prazo. Respostas não equivalem a autenticação de um humano.
- Pedidos DENIED ou revisões já encerradas podem ser importados somente para exibição, sem reabrir a decisão.
- `npm --prefix ai-core run collector:review-browser` cria pedido a partir de fixture sintética e imprime endereço de loopback que deve ser aberto no mesmo dispositivo.
- `docs/COLLECTOR_REVIEW_BROWSER.md` contém instruções e esclarece que o formulário **não autentica usuário real** nem toca no Roblox.
- [CI push aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41387218860) e [CI PR aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41387223580).
- **Não incluído:** instalação do menu Roblox, autenticação do operador, gateway/Render real, qualquer execução ao vivo ou consentimento de proprietário comprovado.

**Pontuação P4 = 8/15; total = 60/100; restam 40 pontos.**
