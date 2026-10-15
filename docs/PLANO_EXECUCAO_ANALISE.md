# Plano de execução — análise e evolução do CAFÉÍNA Collector

**Última atualização:** 2026-10-15  
**Repositório:** `medeirospablo190-alt/Cafe-na-IA`  
**Branch de trabalho/backup:** `backup-coletor-2026-10-15`  
**Referência de arquitetura:** `Badarulnisa/reverse-engine` e fork `medeirospablo190-alt/reverse-enginee`

## Objetivo

Compreender o coletor de ponta a ponta, preservar o que já funciona e incorporar somente as ideias úteis do Reverse Engine: extração de estruturas, normalização, comparação, correlação temporal e relatórios. O Reverse Engine foi pensado para tráfego HTTP/HAR; o CAFÉÍNA observa sessões Roblox em runtime. Não tratar os dois mecanismos de captura como intercambiáveis.

## Requisito obrigatório: funcionar no Android e enviar ao GitHub

O resultado precisa ser funcional no ambiente Android usado pelo projeto, sem presumir que há um PC disponível. A análise ou integração não será considerada concluída só porque o código está no GitHub ou passa em testes isolados.

- **Executar no Android:** identificar o executor/ambiente real, as APIs e permissões disponíveis, os pontos de entrada e as limitações da versão de Lua usada. Não depender de comandos, serviços ou caminhos exclusivos de desktop.
- **Preservar o fluxo de envio existente:** antes de modificar transporte ou backend, documentar como os dados saem do coletor, chegam ao gateway (se aplicável) e são persistidos/espelhados no GitHub. Manter formato, autenticação, nomes/caminhos e compatibilidade dos registros existentes, salvo mudança justificada e testada.
- **Envio eficiente:** manter lotes e limites de tamanho, evitar uploads repetidos, controlar frequência e concorrência, tratar respostas de erro, rate limits e falhas temporárias com backoff.
- **Não perder dados silenciosamente:** confirmar se existe fila/cache persistente, quando um registro é considerado entregue, como ocorre retry após queda de conexão e como evitar duplicação em reenvios. Se algo não existir, documentar antes de projetar alteração.
- **Recursos limitados:** avaliar consumo de memória, CPU, bateria, rede e impacto no FPS; limitar filas e investigações e oferecer interrupção segura quando aplicável.
- **Segurança:** não registrar tokens, cookies ou credenciais em traces/logs; usar somente autenticação autorizada e não contornar anti-cheat, autenticação ou controles de acesso.
- **Validação em camadas:** distinguir (1) inspeção estática, (2) testes automatizados, (3) teste de integração do envio e (4) execução real no Android/jogo. Nunca declarar o nível 4 validado sem evidência de execução real.

### Critérios de aceitação para Android/GitHub

- [ ] Inicializa no ambiente Android alvo sem API incompatível ou erro fatal.
- [ ] Coleta os tipos de evento que o projeto já suporta, com limites e cancelamento funcionando.
- [ ] Consegue serializar e dividir dados grandes sem corromper registros ou ultrapassar limites conhecidos.
- [ ] O caminho de envio atual continua funcionando e o destino no GitHub recebe os dados esperados.
- [ ] Erros de rede/autorização/rate limit são reportados sem travar a coleta nem descartar dados silenciosamente.
- [ ] Retry e retomada após desconexão são testados; duplicação e idempotência são avaliadas.
- [ ] O tamanho dos lotes, o número de requisições e o consumo de recursos são medidos ou, se não for possível medir, explicitamente marcados como não verificados.
- [ ] O teste real no Android é registrado separadamente dos testes feitos no backend ou no ambiente de desenvolvimento.

## Regras de execução

1. **Trabalhar primeiro na branch de backup.** Não alterar `main` sem uma decisão explícita.
2. **Antes de editar:** ler o arquivo atual e as dependências; registrar o motivo e o resultado esperado.
3. **Uma mudança lógica por commit.** Evitar refatorações grandes misturadas com novas funcionalidades.
4. **Não alegar execução de testes sem executá-los.** Distinguir leitura estática, teste executado e comportamento observado em sessão.
5. **Não declarar causalidade só por proximidade temporal.** Relatórios devem distinguir fato, padrão recorrente, hipótese e conclusão confirmada.
6. **Não coletar nem expor segredos desnecessários.** Redigir tokens, cookies, cabeçalhos de autenticação e dados pessoais; minimizar identificadores.
7. **Sem contornar anti-cheat, autenticação, controles de acesso ou proteções de terceiros.** Priorizar observação passiva e testes autorizados, reversíveis e de baixo impacto.
8. **Não substituir a lógica existente por código do Reverse Engine sem justificar compatibilidade, dependências e riscos.**
9. **Manter o coletor responsivo em dispositivos móveis:** limites de memória, CPU, filas e frequência de envio devem continuar sendo verificados.
10. **Preservar o envio funcional para o GitHub:** nenhuma alteração no transporte ou no formato pode ser considerada segura sem teste de compatibilidade.
11. Ao retomar o trabalho, ler primeiro este plano e o registro de progresso antes de reexaminar arquivos.

## Estado inicial — 2026-10-15

### Já consultado (análise parcial, não auditoria completa)

- `Cafeina_Universal_Game_Trace_V3_0.lua`: cabeçalho, configuração e partes iniciais; identificados observadores de remotes, inferência de argumentos, buffers, correlação temporal, investigações limitadas, filas e envio em lotes. O arquivo anuncia limites de memória e salvamento de dados pendentes. **Ainda falta percorrer o arquivo inteiro e seguir as funções-chave.**
- `collector-v3-routes.js`: os testes foram consultados, mas isso não equivale à leitura completa da implementação das rotas.
- `test/collector-v3-routes.test.mjs`: cenários de idempotência, conflitos, arquivos grandes, manifesto/perfil e espelhamento GitHub.
- `test/inventory-trace.test.mjs`: cenário de recebimento, gravação local, endpoint `latest`, status e recibo.
- O gateway foi identificado como parte da arquitetura, mas ainda é necessário mapear seus módulos, rotas e dependências completos.
- Reverse Engine: consultados `app/collectors/extractor.py`, `app/collectors/parser.py`, `app/collectors/generator.py`, `app/core/config.py` e `README_INTEGRATION.md`. O extractor achata JSON aninhado e agrupa registros; parser normaliza campos; generator produz coletores HTTP; configuração centraliza parâmetros. A parte de geração/captura HTTP não deve ser transplantada diretamente para Roblox.

### Observações preliminares registradas (precisam de contexto de origem antes de conclusões)

Um manifesto mencionado na conversa reportou 2,78 MB, 838 observadores de valores, 61 listeners de entrada, 102 remotes novos, 19.674 objetos do Workspace e 36 investigações profundas. Antes de usar esses números como referência de desempenho, localizar o arquivo exato, conferir data/jogo/sessão e entender as definições dos contadores.

### Alterações feitas

- Criada a branch `backup-coletor-2026-10-15` a partir de `main`.
- Nenhum módulo do Reverse Engine foi integrado ao coletor até a criação deste plano.
- Nenhuma alteração funcional do coletor foi feita nesta análise.

## Fases de execução

### Fase 0 — Confirmar a cópia e o ponto de restauração

- [ ] Confirmar que a branch existe e aponta para a revisão esperada.
- [ ] Registrar SHA/commit base de `main` e da branch.
- [ ] Conferir se há alterações anteriores na branch antes de cada nova escrita.
- [ ] Não assumir que a branch é uma cópia independente do repositório: é uma linha de desenvolvimento no mesmo repositório.

**Saída:** referência reproduzível do estado inicial.

### Fase 1 — Inventário completo do repositório

- [ ] Ler README, `package.json`, scripts e dependências.
- [ ] Listar arquivos e identificar pontos de entrada, rotas, serviços, armazenamento, testes e documentação.
- [ ] Mapear variáveis de ambiente e segredos esperados; registrar apenas os nomes, nunca os valores.
- [ ] Identificar versões de protocolo (trace legado e V3), limites de compatibilidade e caminhos de dados.
- [ ] Mapear o fluxo completo: coletor Lua → gateway/API (se aplicável) → persistência → GitHub.
- [ ] Identificar explicitamente o ambiente Android alvo e as funções/APIs disponíveis nele.

**Saída:** inventário de arquivos, diagrama textual do fluxo completo e checklist de compatibilidade Android.

### Fase 2 — Auditoria do coletor Lua

Examinar o arquivo inteiro em blocos e seguir cada função relevante até seus efeitos.

- [ ] Captura passiva de eventos/remotes de entrada e saída.
- [ ] Serialização, truncamento, hashing e inferência de formatos de argumentos.
- [ ] Descoberta de objetos, valores, GUI e estado do personagem/mundo.
- [ ] Buffers temporais, correlação ação/efeito e critérios de confiança.
- [ ] Investigações aprofundadas e testes ativos: gatilhos, limites, cancelamento, efeitos colaterais e salvaguardas.
- [ ] Deduplicação, prioridade, backpressure, limites de memória e proteção de FPS.
- [ ] Cache local, retomada de envio, retries e tratamento de erros.
- [ ] Confirmar APIs de rede/arquivo e compatibilidade com o executor Android real.
- [ ] Interface do coletor e mecanismos para interromper uma investigação.
- [ ] Pontos de risco: dados pessoais, excesso de coleta, falhas de serialização e interferência na sessão.

**Saída:** mapa de funções e fluxo de dados; lista de riscos, bugs potenciais e lacunas com referência a arquivo/linha.

### Fase 3 — Auditoria do backend e da persistência

- [ ] Ler integralmente `collector-gateway.js`, `gateway-main.js` e `collector-v3-routes.js` (ou confirmar os nomes reais no inventário).
- [ ] Mapear todas as rotas, validações de entrada, autenticação, limites de corpo e respostas.
- [ ] Verificar gravação local, nomes de arquivo, isolamento por jogo/sessão, concorrência e recuperação após falhas.
- [ ] Verificar espelhamento GitHub, tokens, tratamento de rate limit, idempotência e conflitos.
- [ ] Confirmar o contrato de envio que o coletor Android realmente usa e não quebrar compatibilidade com clientes existentes.
- [ ] Conferir se endpoints de consulta expõem somente os dados pretendidos.
- [ ] Comparar implementação real com os testes; identificar comportamentos sem teste.
- [ ] Executar testes existentes somente em ambiente controlado, se as dependências/ambiente estiverem disponíveis, e registrar o comando e o resultado.

**Saída:** contrato das rotas, esquema de dados, matriz de testes e falhas encontradas.

### Fase 4 — Analisar amostras reais e a qualidade dos dados

- [ ] Localizar traces reais relevantes e identificar jogo, place, versão, sessão e timestamp.
- [ ] Verificar se os dados são completos, truncados, duplicados ou inconsistentes.
- [ ] Catalogar tipos de registros e campos existentes; quantificar campos ausentes e valores variados.
- [ ] Separar dados observados de inferências feitas pelo próprio coletor.
- [ ] Confirmar a origem e a semântica de cada métrica antes de usá-la como baseline.
- [ ] Criar amostras sanitizadas para testes, sem tokens ou identificadores desnecessários.

**Saída:** dicionário de dados, baseline e conjunto de testes reproduzível.

### Fase 5 — Fechar a análise do Reverse Engine

- [ ] Ler README, dependências e configuração completa.
- [ ] Seguir o fluxo de entrada HAR → extração → normalização → relatório.
- [ ] Identificar algoritmos independentes de HTTP que podem ser reutilizados conceitualmente.
- [ ] Separar funcionalidades específicas de web/API (HAR, cookies, headers, paginação HTTP, fingerprints TLS/JA3 e geração de clientes HTTP).
- [ ] Conferir licença e atribuição antes de copiar código, não apenas ideias.
- [ ] Comparar formatos de dados e decidir se é melhor portar lógica, criar implementação própria ou apenas adotar o formato de relatório.

**Saída:** tabela “reaproveitar / adaptar / não portar”, com justificativa e dependências.

### Fase 6 — Projeto de integração mínima

Priorizar uma camada de análise offline no backend, sem mudar a captura Lua inicialmente.

- [ ] Normalizador de registros com versão de esquema.
- [ ] Descoberta de tipos/campos e estruturas recorrentes.
- [ ] Comparação entre sessões e detecção de mudanças.
- [ ] Linha do tempo que correlacione eventos e alterações sem declarar causalidade automaticamente.
- [ ] Relatórios JSON/Markdown pesquisáveis com evidências e nível de confiança.
- [ ] Deduplicação e processamento incremental para não reprocessar todo o histórico.
- [ ] Redação de segredos e minimização de dados.
- [ ] Definir critérios de aceitação antes de implementar.

**Saída:** desenho técnico e testes de aceitação aprovados antes de alterar o código.

### Fase 7 — Implementação em incrementos pequenos

- [ ] Criar o primeiro módulo de análise isolado.
- [ ] Adicionar testes com fixtures sanitizadas e casos de erro.
- [ ] Comparar resultados do módulo com inspeção manual.
- [ ] Medir tempo, memória e tamanho de saída.
- [ ] Fazer commit separado para cada funcionalidade.
- [ ] Atualizar este plano e o registro de progresso após cada commit.
- [ ] Só depois considerar integração opcional com a API; evitar mudanças simultâneas no coletor Lua e no backend.

**Saída:** integração incremental, testada e reversível.

### Fase 8 — Validação e decisão de entrega

- [ ] Executar a suíte relevante e registrar testes aprovados/falhos/não executados.
- [ ] Verificar compatibilidade com traces antigos e novos.
- [ ] Confirmar que os limites de memória, fila, latência e envio continuam funcionando.
- [ ] Validar separadamente o fluxo de upload para o GitHub e o comportamento real no Android.
- [ ] Revisar segurança, privacidade e comportamento em falhas.
- [ ] Comparar relatórios novos com o baseline.
- [ ] Documentar limitações conhecidas e procedimento de rollback.
- [ ] Só propor merge para `main` após revisão explícita.

**Saída:** relatório final com evidências, diferenças, testes e recomendação de merge ou não merge.

## Registro de progresso — atualizar a cada sessão

Use este formato ao terminar cada bloco de trabalho:

- **Data:**
- **Fase / tarefa:**
- **Arquivos lidos:**
- **Arquivos alterados:**
- **O que foi confirmado (com evidência):**
- **O que é apenas hipótese:**
- **Testes executados e resultados:**
- **Android real testado?** Sim / não; dispositivo/ambiente e resultado.
- **Envio GitHub testado?** Sim / não; destino/resultado (sem registrar credenciais).
- **Commit/branch:**
- **Problemas ou bloqueios:**
- **Próxima ação única:**

## Formato do inventário por arquivo

| Campo | O que registrar |
|---|---|
| Caminho | Caminho exato no repositório |
| Papel | Responsabilidade do arquivo |
| Entradas/saídas | Dados recebidos e produzidos |
| Dependências | Módulos e serviços chamados |
| Estado | Não visto / parcial / lido / testado |
| Evidência | Linhas, função ou teste que confirma |
| Risco | Privacidade, segurança, desempenho, integridade |
| Próxima ação | Uma tarefa objetiva |

## Critério para considerar uma tarefa concluída

Uma tarefa só passa a “concluída” quando o escopo está claro, a evidência foi registrada, as dependências relevantes foram verificadas e os testes aplicáveis foram executados ou explicitamente marcados como não executados. “Li o arquivo” não significa “validei o comportamento”. Um teste em backend não prova compatibilidade Android; um envio simulado não prova que o upload real está funcionando.

## Próxima ação recomendada

Começar pela **Fase 0** e depois executar a **Fase 1**: confirmar a base da branch e fazer o inventário completo do repositório. Em seguida, mapear o caminho real de envio ao GitHub antes de modificar qualquer parte dele. Não integrar código novo antes de concluir a auditoria do fluxo atual.


## Registro de progresso — 2026-10-15 (início da execução)

- **Fase / tarefa:** Fase 0 concluída; Fase 1 iniciada.
- **Arquivos lidos:** `README.md`, `package.json`, `.env.example`, `.gitignore`, `.github/workflows/cafeina-trace-v3-ci.yml`, `collector-gateway.js`, trechos relevantes de `gateway-main.js`, `collector-v3-routes.js` e `Cafeina_Universal_Game_Trace_V3_0.lua).
- **Base confirmada:** `main` está no commit `4c50fb8193bfa08a9d56426ddea42d053360354b`. A branch `backup-coletor-2026-10-15` está 2 commits à frente e 0 atrás; a comparação indica que o único arquivo alterado em relação a `main` é este plano. Não houve mudança funcional no coletor.
- **Inventário inicial:** árvore recursiva reporta 1.584 entradas (1.524 arquivos e 60 diretórios), incluindo muitos traces JSON históricos versionados junto do código. Isso pode tornar clones/checkout e diffs pesados; avaliar depois se é intencional, sem remover histórico automaticamente.
- **Arquitetura confirmada:** `npm start` inicia `collector-gateway.js`, que importa `gateway-main.js`; o gateway instala as rotas V3 por `collector-v3-routes.js`. Dependência de runtime do gateway: Express 5.1.x; o projeto declara Node como ESM e CI usa Node 22.
- **Fluxo V3 confirmado por leitura estática:** o Lua envia lotes JSON para `https://cafe-na-ia.onrender.com/api/inventory-trace-v3/batch`; o gateway valida o lote, grava arquivo local, consulta o caminho correspondente no GitHub e cria/atualiza o conteúdo via API GitHub. A resposta positiva do cliente exige `ok=true` e confirmação `github.configured=true` + `github.mirrored=true`.
- **Proteções de transporte observadas:** lote alvo de aproximadamente 1,75 MiB; cliente guarda o corpo exato do lote em voo/outbox quando as funções de arquivo estão disponíveis; cache persistente guarda fila e estado de retomada; o servidor verifica checksum e retorna conflito 409 se o mesmo índice/run tiver conteúdo diferente. Há retries para falhas transitórias e bloqueio de retry cego para erros determinísticos.
- **Compatibilidade Android ainda não comprovada:** o script procura APIs do executor para requisição HTTP e funções de arquivo (`request`, `http_request`, `syn.request`, `writefile`, `readfile`, `isfile`, `delfile`). Se o executor Android não disponibilizar alguma delas, upload ou retomada pode ficar limitado. Ainda não foi executado no aparelho nem em sessão Roblox nesta etapa.
- **Configuração backend documentada:** `.env.example` contém nomes de variáveis para diretório persistente, token/repositório/branch GitHub, limites V2/V3 e limite de corpo V3 (padrão no código: `3mb`). Nenhum valor de segredo foi coletado neste inventário.
- **Testes:** não executados por esta análise; apenas foi lido o workflow que define `npm run check`, `npm test` e compilação com Luau no CI. Leitura do workflow não equivale a teste aprovado.
- **Arquivos alterados nesta etapa:** nenhum arquivo funcional; este registro de progresso no plano.
- **Próxima ação única:** concluir a Fase 1 mapeando o contrato completo de resposta/erro do endpoint V3, a recuperação de cache/outbox no cliente e o conjunto de testes correspondente, antes de propor qualquer mudança de código.


### Complemento de progresso — contrato de envio e testes

- **Contrato de resposta V3:** sucesso retorna HTTP 201 com `ok`, `runId`, `gameId`, `placeId`, `batchIndex`, `batchKind`, `checksum` e `github: { configured: true, mirrored: true, path }`. O cliente exige confirmação explícita do espelhamento GitHub antes de avançar o ACK local.
- **Falhas do endpoint:** ausência de token retorna 503; limites de frequência podem retornar 429; payload inválido retorna 400; conflito de conteúdo no mesmo caminho/lote retorna 409; lote acima do limite do parser retorna 413; falha de gravação local retorna 500; falha ao confirmar no GitHub retorna 502. No manifesto, a gravação do lote pode ter ocorrido mesmo se a finalização do perfil/latest falhar, e o endpoint devolve 502 com mensagem de finalização parcial.
- **Idempotência:** o servidor usa caminho determinístico por `gameId/placeId/runId/batchIndex-batchKind` e compara `contentChecksum`. Repetição idêntica é aceita; mesmo índice com corpo semanticamente diferente é rejeitado para evitar sobrescrever dados.
- **Outbox/cache:** o cliente restaura cache somente para o mesmo `gameId`; valida sequência do índice e contagem de itens ao restaurar o corpo em voo. O corpo exato pendente é removido após ACK. É necessário testar o cenário em que as funções de arquivo não existem no executor, porque o envio continua possível, mas a durabilidade local fica degradada.
- **Cobertura dos testes lidos:** `test/collector-v3-routes.test.mjs` cobre health, repetição idempotente, conflito 409, leitura raw de arquivos GitHub acima de 1 MB, manifesto e perfil; `test/inventory-trace.test.mjs` inicia o gateway em processo separado e cobre persistência local/endpoint latest/status no fluxo legado. Esses testes não executam o Lua no Android.
- **CI:** `.github/workflows/cafeina-trace-v3-ci.yml` declara Node 22, `npm run check`, `npm test` e compilação Luau. Nesta sessão não foi executado o comando local nem foi confirmada uma execução recente desse workflow específico. Uma execução bem-sucedida do workflow de sincronização de traces não deve ser tratada como aprovação dos testes V3.
- **Ponto de atenção a investigar, sem conclusão antecipada:** o gateway faz GET do arquivo no GitHub antes do PUT para cada lote, além das gravações do manifesto/latest e do perfil. Isso ajuda a detectar conflito/repetição, mas pode consumir chamadas da API do GitHub em sessões grandes; medir frequência real e limites antes de mudar a estratégia.


### Complemento de progresso — recuperação e pontos de validação

- **Cliente Lua — persistência do envio:** antes de POST, o cliente serializa o lote e tenta persistir `batch.body` na outbox. Se a gravação falhar, registra `outbox_write`, mas continua tentando enviar pela rede. Isso é um modo degradado: a sessão pode funcionar, porém a recuperação após encerramento do executor deixa de estar garantida. O teste Android deve verificar se o aviso é visível e se `writefile/readfile/isfile/delfile` realmente funcionam no executor.
- **ACK do cliente:** o cliente só considera o lote concluído depois do retorno positivo do servidor e da confirmação explícita de espelhamento GitHub. Isso evita marcar como entregue um lote cuja gravação remota falhou.
- **Persistência do servidor:** o lote é gravado localmente antes de ser espelhado no GitHub. Se o espelhamento falhar, o endpoint retorna erro e o retry pode reutilizar o arquivo local existente e tentar concluir o espelhamento. Esse comportamento é desejável para recuperação, mas depende da persistência do disco no host Render; a durabilidade após reinício/novo deploy deve ser confirmada na configuração real do serviço.
- **Risco de latência/limites:** para cada lote novo o backend lê o caminho no GitHub e, se ainda não existir, cria o arquivo. O manifesto também atualiza perfil e `latest.json`. Não mudar isso sem medição: a checagem é parte da idempotência e da proteção contra sobrescrita.
- **Compatibilidade dos testes:** os testes de gateway usam um GitHub falso local e cobrem idempotência, conflito, arquivos grandes, manifesto/perfil e fluxo legado. Eles não validam rede móvel, permissões do executor, autenticação real do GitHub, quotas reais da API ou execução do script Lua dentro do Roblox.
- **Execução dos testes nesta sessão:** ainda não realizada. O conector GitHub disponível permite ler e gravar arquivos, mas não executar `npm test` no repositório. Não declarar CI verde sem consultar um resultado de execução específico.
- **Inventário / próxima etapa:** Fase 1 está parcialmente concluída. Para encerrar, ainda falta mapear a rota legada e a configuração real de deploy/armazenamento do Render, além de conferir os estados de erro do cliente e como são apresentados na UI. A seguir, auditar os limites de dados e os pontos de encerramento/reinício do coletor, mantendo as mudanças funcionais suspensas até haver um teste reproduzível.


## Análise cruzada: Reverse Engine → CAFÉÍNA Collector

Repositório analisado: https://github.com/medeirospablo190-alt/reverse-enginee (branch `main`). Esta fase mapeia componentes reutilizáveis; não copia o framework inteiro nem substitui o coletor Lua.

### Estrutura do Reverse Engine mapeada
- `app/core/har_parser.py`: entrada de HAR e normalização para um registro por chamada (host, path, método, status, cabeçalhos, query, corpos, tempo).
- `app/collectors/extractor.py`: identifica registros dentro de envelopes JSON, achata objetos/listas e conserva metadados de origem.
- `app/core/path_templater.py`: agrupa caminhos concretos por template e extrai parâmetros de caminho.
- `app/core/openapi_builder.py`: combina amostras para inferir esquemas, preservando diferenças de tipo.
- `app/core/pagination_stitcher.py`: tenta inferir paginação por sequências de parâmetros e cursor; confiança deve ser mantida explícita, não tratada como certeza.
- `app/core/system_detector.py`: resume tráfego por host.
- `app/core/report_builder.py`: gera relatórios XLSX com união de colunas e abas de resumo/achados.
- `app/core/vuln_scanner.py` e `app/core/bot_defense_scanner.py`: análises passivas do HAR. São específicas de HTTP/web e não substituem observação de estado em Roblox.
- `README_INTEGRATION.md`: confirma fluxo de entrada HAR → normalização → extração → relatório; registra limitações com binários e paginação e alerta para sanitizar tokens capturados.

### O que pode ser adaptado para o coletor
1. **Camada de normalização offline (prioridade alta):** criar um analisador separado que leia lotes V3 já recebidos e normalize campos comuns, sem alterar o formato que o Lua envia.
2. **Achatar estruturas com limites:** reaproveitar a ideia de `flatten` para produzir tabelas de atributos/argumentos e caminhos, mas com limites de profundidade, número de nós, tamanho de strings e proteção contra estruturas enormes/cíclicas.
3. **Inferência de esquema por múltiplas amostras:** adaptar a união de tipos/propriedades do OpenAPI para os argumentos e registros observados, mantendo contagens, amostras e confiança; não concluir semântica só pelo nome de um campo.
4. **Agrupamento por caminho lógico:** adaptar templating para caminhos de instâncias/objetos Roblox, usando segmentos e classes conhecidas em vez de heurísticas de IDs numéricos de URL.
5. **Reconstrução temporal:** usar o timestamp, ordem de eventos e referências compartilhadas para agrupar observações relacionadas; a detecção de paginação do Reverse não é diretamente aplicável, mas seu padrão de inferência multi-amostra e confiança pode ser.
6. **Relatórios e diferenças entre sessões:** adaptar o relatório XLSX/JSON para comparar runs, classes de Remote, tipos/forma de argumentos, propriedades e cobertura. Isso pode ocorrer no ambiente online/backend, preservando o requisito de coleta no Android.
7. **Higiene de dados:** incorporar redaction de tokens/identificadores sensíveis em logs e relatórios compartilháveis; não registrar segredos.

### O que não deve ser transplantado diretamente
- HAR parser, detector de host e paginador: dependem de tráfego HTTP de navegador, enquanto a coleta principal é feita no runtime Roblox.
- Geradores de cURL/Playwright e técnicas de impersonação de TLS: não melhoram a captura de estado Roblox e podem incentivar replay ou contornar controles; não entram na adaptação.
- Scanner de vulnerabilidade web: só faz sentido para auditar endpoints HTTP autorizados, fora do caminho de coleta do jogo.
- Dependências pesadas Python/Redis/SQLite: não adicionar ao script Lua/Android. Se um analisador offline Python for útil, deve ficar separado do runtime e ser opcional.

### Arquitetura proposta de integração
`Roblox/Lua no Android → lotes V3 atuais → gateway/espelho GitHub → analisador offline independente → normalização + deduplicação + inferência de esquemas + comparação entre sessões → relatório JSON/CSV/XLSX`.

O contrato atual de envio e a outbox devem permanecer estáveis enquanto a análise offline é construída. O analisador deve ser reexecutável e idempotente, guardar a proveniência de cada inferência (arquivo/lote/índice/tempo), distinguir observação de hipótese e nunca editar os dados brutos recebidos.

### Estado e próximos passos
- Mapeamento inicial de módulos do Reverse Engine concluído por leitura estática dos arquivos principais.
- Nenhum código do Reverse Engine foi copiado para o coletor; nenhuma alteração funcional foi feita.
- Próxima tarefa: desenhar o esquema normalizado de saída para Trace V3 e mapear exemplos reais de lotes/campos existentes no repositório; depois criar testes com fixtures anonimizadas e comparar os resultados com os dados brutos.
