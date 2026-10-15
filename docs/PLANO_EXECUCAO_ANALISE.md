# Plano de execução — análise e evolução do CAFÉÍNA Collector

**Última atualização:** 2026-10-15  
**Repositório:** `medeirospablo190-alt/Cafe-na-IA`  
**Branch de trabalho/backup:** `backup-coletor-2026-10-15`  
**Referência de arquitetura:** `Badarulnisa/reverse-engine` e fork `medeirospablo190-alt/reverse-enginee`

## Objetivo

Compreender o coletor de ponta a ponta, preservar o que já funciona e incorporar somente as ideias úteis do Reverse Engine: extração de estruturas, normalização, comparação, correlação temporal e relatórios. O Reverse Engine foi pensado para tráfego HTTP/HAR; o CAFÉÍNA observa sessões Roblox em runtime. Não tratar os dois mecanismos de captura como intercambiáveis.

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
10. Ao retomar o trabalho, ler primeiro este plano e o registro de progresso antes de reexaminar arquivos.

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
- [ ] Criar um mapa de dependências entre coletor Lua, gateway, API, persistência local e espelhamento GitHub.

**Saída:** inventário de arquivos e diagrama textual do fluxo completo.

### Fase 2 — Auditoria do coletor Lua

Examinar o arquivo inteiro em blocos e seguir cada função relevante até seus efeitos.

- [ ] Captura passiva de eventos/remotes de entrada e saída.
- [ ] Serialização, truncamento, hashing e inferência de formatos de argumentos.
- [ ] Descoberta de objetos, valores, GUI e estado do personagem/mundo.
- [ ] Buffers temporais, correlação ação/efeito e critérios de confiança.
- [ ] Investigações aprofundadas e testes ativos: gatilhos, limites, cancelamento, efeitos colaterais e salvaguardas.
- [ ] Deduplicação, prioridade, backpressure, limites de memória e proteção de FPS.
- [ ] Cache local, retomada de envio, retries e tratamento de erros.
- [ ] Interface do coletor e mecanismos para interromper uma investigação.
- [ ] Pontos de risco: dados pessoais, excesso de coleta, falhas de serialização e interferência na sessão.

**Saída:** mapa de funções e fluxo de dados; lista de riscos, bugs potenciais e lacunas com referência a arquivo/linha.

### Fase 3 — Auditoria do backend e da persistência

- [ ] Ler integralmente `collector-gateway.js`, `gateway-main.js` e `collector-v3-routes.js` (ou confirmar os nomes reais no inventário).
- [ ] Mapear todas as rotas, validações de entrada, autenticação, limites de corpo e respostas.
- [ ] Verificar gravação local, nomes de arquivo, isolamento por jogo/sessão, concorrência e recuperação após falhas.
- [ ] Verificar espelhamento GitHub, tokens, tratamento de rate limit, idempotência e conflitos.
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

Uma tarefa só passa a “concluída” quando o escopo está claro, a evidência foi registrada, as dependências relevantes foram verificadas e os testes aplicáveis foram executados ou explicitamente marcados como não executados. “Li o arquivo” não significa “validei o comportamento”.

## Próxima ação recomendada

Começar pela **Fase 0** e depois executar a **Fase 1**: confirmar a base da branch e fazer o inventário completo do repositório. Não integrar código novo antes de concluir a auditoria do fluxo atual.
