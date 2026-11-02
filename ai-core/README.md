# CAFEÍNA AI Core — início da construção

Módulo isolado para o sistema de agentes que vai estudar **jogos próprios ou autorizados**, receber evidências do coletor V3, propor investigações e futuramente gerar **Luau original**.

## Estado atual

Esta versão é **um protótipo local de leitura/planejamento (DRY_RUN)**, não um sistema de IA conectado. Ela importa um batch + latest V3, confere identidade da sessão, resume os tipos de registros sem transportar campos de jogador, cria uma proposta de observação **não executável** e mostra progresso auditável.

**Não faz**: chamadas a modelos pagos, conexão ativa com REA, GitHub, Roblox ou Render, execução de ferramentas em jogo, programação ou publicação.

## Executar (Node 22+)

```bash
cd ai-core
npm run validate
npm run demo
npm run progress
node src/cli.mjs /caminho/0001-data.json /caminho/latest.json
```

Todos os testes usam apenas **dados sintéticos** e bibliotecas nativas do Node. Não há arquivos de jogadores reais nas fixtures.

## Sessão completa e memória por jogo

Com Node 22+, o importador agora aceita **vários lotes** de uma mesma sessão, um manifesto e um perfil opcional. Ele valida o índice de cada arquivo, remove duplicatas idênticas, rejeita divergências e identifica lotes ausentes.

```bash
cd ai-core
node src/session-cli.mjs \
  --session-dir /caminho/da/sessao \
  --manifest /caminho/latest.json \
  --profile /caminho/perfil.json \
  --store /pasta/privada/indice \
  --out /pasta/privada/relatorio.json
```

`--store` e `--out` são opcionais. A memória `<gameId>.json` fica no disco local do ambiente executor, **não é enviada automaticamente ao GitHub**. A fase P1 está em **14/15**, faltando persistência segura entre runners e revisão da privacidade histórica. Em runners temporários, será necessário implementar persistência autenticada em etapa posterior. Nenhuma confiança é elevada automaticamente a VALIDATED.

## Documentação

- `docs/ROADMAP.md` — plano até 100% e critérios.
- `docs/ARCHITECTURE.md` — componentes e contratos futuros.
- `docs/SECURITY.md` — privacidade e permissões.
- `plan/progress.json` — fonte calculável do percentual.

O coletor V3, o gateway e as configurações de produção continuam intocados.

## Agentes e memoria GitHub: incremento atual

O comando `npm run agents:demo` executa quatro papeis determinísticos (Investigadora, Crítica, Pesquisadora, Coordenadora) usando somente dados sintéticos. Eles produzem recomendações e não executam ações. O módulo `src/model.mjs` acrescenta uma interface opcional para um servidor local compatível com Ollama, com saída restrita a ferramentas permitidas, limite de tempo e nenhuma dependência de APIs pagas. O modelo foi **executado em um teste temporário no GitHub Actions**, mas não fica permanentemente ativo.

O GitHub possui a branch `cafeina-ai-knowledge` para memória saneada. `src/knowledge-github.mjs` combina sessões com controle de conflito e escrita condicionada a opt-in. A CI experimenta a leitura em modo `DRY_RUN`; a publicação pela API ainda depende de execução manual e revisão. O workflow `.github/workflows/cafeina-ai-knowledge.yml` só será acionável normalmente após sua aprovação/mesclagem na branch padrão.

## Progresso auditado deste incremento

O contador oficial esta em `plan/progress.json`: **40/100 pontos**. A CI aprovada testou um dry-run de consulta a memoria no proprio GitHub, mas nao realizou uma gravacao real. O modelo de linguagem foi testado com dados sintéticos. Falta integrar agentes com o modelo na rotina completa, criar a fila de missoes e integrar o menu.

A branch `cafeina-ai-knowledge` foi criada separadamente, sem alterar a main. A implementacao da equipe de agentes e do armazenamento permanece no PR #228.

## Modelo aberto realmente testado e diario de decisoes

O GitHub Actions executou um modelo `qwen2.5:0.5b` em CPU via Ollama (com ambiente e tempo limitados). O teste foi feito **somente com dados sinteticos** e terminou com uma recomendacao validada de `watch_state`, sem executar nenhuma ferramenta.

- Workflow one-off: `.github/workflows/cafeina-ai-local-model-smoke.yml`
- Cliente com schema JSON estrito: `src/model.mjs`
- Registro com campos estritamente permitidos: `src/decision-journal.mjs`
- Pipeline real de coleta historica → agentes por regras → diario: `src/agent-report-cli.mjs`
- Artefato sintetico gerado com a IA real expira em 7 dias: [Execucao aprovada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41353005800)

**Importante:** nenhum modelo foi implantado como servico sempre ligado, e nenhum dado real de jogador foi enviado a inferencia. O modelo pequeno nao basta para Engenharia Reversa complexa. Continua faltando conectar REA, menu Roblox e publicar memoria de forma segura.

## Missões offline com recuperação e especialistas (Fase P2)

O sistema agora possui um fluxo **local e somente de análise**, separado dos comandos do Roblox:
- `src/task-engine.mjs` cria tarefas determinísticas por sessão e manifesto, com estados, revisão, limites de tentativas, lease, prazo, cancelamento e recuperação após interrupção.
- `src/specialists.mjs` adiciona Arquiteta, Programadora e Testadora como papéis determinísticos. Eles apenas identificam requisitos ainda não comprovados e desenham verificações; **não geram código nem executam testes ativos**.
- `src/planning-demo.mjs` integra relatório V3 saneado, Coordenadora e especialistas. Exemplo:
```bash
node ai-core/src/planning-demo.mjs /caminho/relatorio-saneado.json /pasta-privada
```

**Persistência**: a tarefa sobrevive à reinicialização do processo quando seu arquivo é conservado no mesmo disco. Ainda **não** é gravada automaticamente na branch de memória nem recuperável entre dois runners independentes. A integração GitHub ↔ Roblox permanece inexistente.

## Persistencia entre runners e REA

- `src/github-task.mjs` lê e sincroniza estados saneados de tarefas na branch `cafeina-ai-knowledge`, usando SHA e revisões estritas. `dryRun=true` impede escrita acidental.
- Um runner do GitHub Actions salvou uma tarefa **sintética**, e outro runner a recuperou de forma independente. [Resultado verificado](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41362546343). A persistência ainda não foi ligada à execução normal dos agentes.
- `src/rea-adapter.mjs` prepara handoffs de metadados da CAFEÍNA para investigação REA. Não converte falsamente referencias `v3:` em Evidence autenticada.
- Um workflow temporário testou o comando de ledger do REA 6.7.0 com bundle vazio: [Execução verificada](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41362281164). Essa prova não valida mecânicas Roblox.
- `src/planning-demo.mjs` emite agora os dois artefatos: plano dos especialistas e handoff REA.

**Pontuação oficial atual: 40/100, faltam 60 pontos.** A `main`, o gateway e o coletor não foram alterados.
## Canal do menu — simulador P3

- `src/menu-proposal.mjs`: propostas e recibos que nunca concedem autorização.
- `src/github-menu-queue.mjs`: fila imutável no GitHub; gravação real verificada apenas com metadados sintéticos.
- `src/menu-gateway-sim.mjs`: HTTP local com polling, confirmação e resposta de não execução.
- `npm run menu:demo`: prova do fluxo completo usando fixtures sintéticas.

Consulte `docs/MENU_BRIDGE.md` antes de qualquer integração com Roblox real.

## ACK e respostas com estado versionado

Adicionado o ciclo de recibos seguro em `src/menu-delivery-state.mjs` e
armazenamento opcional de metadados no GitHub por
`src/github-menu-receipts.mjs`. Um teste de ponta a ponta usa gateway
HTTP local + API GitHub **simulada** para testar entrega, ACK,
recusa, repetição e falha fechada quando o armazenamento está indisponível.
Ainda não há endpoint de produção nem comunicação Roblox real.

## Fluxo GitHub real de propostas e recibos — 48/100

[Workflow aprovado com três runners independentes](https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365207503): proposta sintética publicada na branch de conhecimento, entrega via gateway HTTP **simulado** e confirmação de NOT_EXECUTED persistida na API GitHub real. Não foram usadas informações de jogadores e nenhuma ferramenta executou código Roblox.

**Estado atual: 48/100 pontos.** Ainda faltam autenticação do menu real, integração ao gateway do Render, autorização de ferramentas e provas em experiência própria.
