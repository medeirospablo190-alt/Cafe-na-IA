# Canal de propostas GitHub → gateway → menu (P3)

## Implementado em ambiente isolado

1. Um relatório V3 saneado gera uma proposta `cafeina_ai_menu_proposal` com IDs de jogo/sessão, hash do manifesto, referências de observação e prazo.
2. Somente ferramentas de observação passiva `watch_state` e `observe_gui` estão previstas. Toda proposta tem `approvalRequired: true`, `approved: false` e `executable: false`.
3. `github-menu-queue.mjs` oferece leitura e gravação de propostas imutáveis na branch `cafeina-ai-knowledge` sob `ai-core/mission-queue/<gameId>/<missionId>.json`. O padrão é `dryRun=true`. A gravação real dessa fila ainda não foi testada.
4. `menu-gateway-sim.mjs` oferece servidor HTTP de teste somente em `127.0.0.1`. Ele valida token opaco de simulação, sessão, prazo, limites de polling e mensagens.
5. O simulador permite apenas `RECEIVED`, `DECLINED` e `NOT_EXECUTED`. Nenhuma dessas mensagens aprova nem executa uma ferramenta.
6. Testes cobrem a sequência API GitHub simulada → HTTP loopback → menu simulado → confirmação e recusa.

## Estados do simulador

`QUEUED → DELIVERED → ACKNOWLEDGED → CLOSED_NO_EXECUTION`

A entrega pode ser repetida; o ACK requer entrega prévia; o resultado requer ACK. Respostas conflitantes, vencidas ou de outra sessão são recusadas. Há limite de 20 polls.

## Falta antes de integrar com Roblox

- Implantar a leitura de propostas no gateway real, com autenticação e identidade verificadas no servidor.
- Validar escrita/leitura da fila real com uma proposta **sintética**, antes de transportar sessões reais.
- Vincular cada sessão autorizada a jogo, lugar e execução, com verificação de permissões.
- Mostrar propostas e estado no menu, inclusive a possibilidade de recusa.
- Persistir ACK e resultados com deduplicação, revisão, prazo e logs saneados.
- Criar um protocolo separado de aprovação explícita para observações ativas.
- Testar somente em experiências próprias ou autorizadas.

**Segurança:** nunca enviar tokens do GitHub para Lua de cliente. O token do simulador não é autenticação Roblox. O gateway real e o coletor permanecem sem alterações. Não existe executor remoto nesse módulo.

## Testar

Use Node.js 22+ e execute `npm --prefix ai-core test`, `npm --prefix ai-core run menu:demo` e `npm --prefix ai-core run check`. Todos os testes usam apenas dados sintéticos.
