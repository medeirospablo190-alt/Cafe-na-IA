# Canal de propostas GitHub → gateway → menu (P3)

## Implementado em ambiente isolado

1. Um relatório V3 saneado gera uma proposta `cafeina_ai_menu_proposal` com IDs de jogo/sessão, hash do manifesto, referências de observação e prazo.
2. Somente ferramentas de observação passiva `watch_state` e `observe_gui` estão previstas. Toda proposta tem `approvalRequired: true`, `approved: false` e `executable: false`.
3. `github-menu-queue.mjs` oferece leitura e gravação de propostas imutáveis na branch `cafeina-ai-knowledge` sob `ai-core/mission-queue/<gameId>/<missionId>.json`. O padrão é `dryRun=true`. A gravação real foi testada **somente com propostas sintéticas** no GitHub Actions, sem conexão com Roblox.
4. `menu-gateway-sim.mjs` oferece servidor HTTP de teste somente em `127.0.0.1`. Ele valida token opaco de simulação, sessão, prazo, limites de polling e mensagens.
5. O simulador permite apenas `RECEIVED`, `DECLINED` e `NOT_EXECUTED`. Nenhuma dessas mensagens aprova nem executa uma ferramenta.
6. Testes cobrem a sequência API GitHub simulada → HTTP loopback → menu simulado → confirmação e recusa.

## Estados do simulador

`QUEUED → DELIVERED → ACKNOWLEDGED → CLOSED_NO_EXECUTION`

A entrega pode ser repetida; o ACK requer entrega prévia; o resultado requer ACK. Respostas conflitantes, vencidas ou de outra sessão são recusadas. Há limite de 20 polls.

## Falta antes de integrar com Roblox

- Implantar a leitura de propostas no gateway real, com autenticação e identidade verificadas no servidor.
- Definir expurgo, retenção e revisão de privacidade dos arquivos de teste já gravados na branch de conhecimento.
- Vincular cada sessão autorizada a jogo, lugar e execução, com verificação de permissões.
- Mostrar propostas e estado no menu, inclusive a possibilidade de recusa.
- Persistir ACK e resultados com deduplicação, revisão, prazo e logs saneados.
- Criar um protocolo separado de aprovação explícita para observações ativas.
- Testar somente em experiências próprias ou autorizadas.

**Segurança:** nunca enviar tokens do GitHub para Lua de cliente. O token do simulador não é autenticação Roblox. O gateway real e o coletor permanecem sem alterações. Não existe executor remoto nesse módulo.

## Testar

Use Node.js 22+ e execute `npm --prefix ai-core test`, `npm --prefix ai-core run menu:demo` e `npm --prefix ai-core run check`. Todos os testes usam apenas dados sintéticos.

## Registro durável de ACK e respostas (em teste)

O novo módulo `src/menu-delivery-state.mjs` valida a evolução estrita
`QUEUED → DELIVERED → ACKNOWLEDGED → CLOSED_NO_EXECUTION`.
Cada evento aumenta a revisão; mensagens repetidas são idempotentes e
respostas finais contraditórias são rejeitadas. Os campos aceitos não incluem
usuários, texto livre, argumentos de remotes, scripts ou autorização de execução.

O adaptador `src/github-menu-receipts.mjs` permite armazenar **somente o estado
saneado** em `cafeina-ai-knowledge/ai-core/menu-receipts/<gameId>/<missionId>.json`,
validando SHA, conteúdo, identidade, prazo e revisões. A escrita é opt-in
(`dryRun=true` por padrão), com tentativas limitadas após conflitos da API.

O gateway HTTP isolado agora aceita um callback opcional `persistEvent`:
se houver erro de armazenamento, retorna HTTP 503 e **não confirma**
entrega, ACK ou conclusão. Os testes verificam o percurso com uma API do
GitHub **simulada**, incluindo reinicialização lógica por nova leitura,
idempotência e indisponibilidade da API.

**Agora comprovado com dados sintéticos:** persistência de propostas e recibos no GitHub real. **Ainda não comprovados:** sessão Roblox autenticada, gateway/Render real, interface de menu no dispositivo ou execução de ferramentas. O simulador continua
exclusivamente em loopback, não fornece credenciais reais e não deve
ser usado como gateway de produção.

## Teste de comunicação via GitHub real (somente sintético)

O workflow `.github/workflows/cafeina-ai-menu-real-roundtrip.yml` executa três jobs independentes:
1. publicar uma proposta passiva `approved=false` e `executable=false`;
2. recuperar a proposta, entregá-la ao menu **simulado** por HTTP local, registrar ACK e NOT_EXECUTED após cada gravação via API do GitHub;
3. ler, em novo runner e somente leitura, os arquivos de proposta e recibo, validando a revisão e ausência de execução.

Resultado aprovado: https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41365207503

Este workflow não se comunica com Roblox, não altera o Render e não cria autorização de execução. O token GitHub só é usado no runner do servidor simulado, enquanto o menu de teste envia apenas token opaco local. A autenticação Roblox de produção continua pendente. O workflow não é agendado nem fica permanentemente ativo.
