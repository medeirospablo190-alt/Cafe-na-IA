# P4 — Catálogo de ferramentas do coletor (protótipo offline)

## O que funciona agora

O módulo `src/collector-tool-sandbox.mjs` implementa um contrato fechado
de ferramentas **passivas e somente de prévia de metadados**:

| Ferramenta | Fonte | Limite | Ações reais |
| --- | --- | --- | --- |
| `watch_state` | contagem e referências de `remote_outbound` | 10 s | Não |
| `observe_gui` | contagem e referências de `gui_state` | 10 s | Não |

Nenhuma ferramenta pode chamar Roblox, disparar remotes, ler o jogo ao vivo,
executar Luau ou modificar estado do coletor. As ferramentas são **nomes
de planejamento**, não executores.

Cada prévia exige:
- proposta saneada de uma mesma sessão e manifesto;
- referências de evidência existentes no relatório V3 saneado;
- um verificador de *fixture sintética* injetado pelo próprio teste;
- ID de tentativa `trial-<16 hex>` e prazo de proposta válido;
- até **2 tentativas de 10 segundos** por instância, no máximo 20 s no total.

O retorno contém somente IDs de sessão, referências V3, quantidade truncada
em 1.000, hash de proveniência, contador, orçamento e flags explícitas
`executedInRoblox=false`, `realToolExecutions=0` e
`approvedForRealExecution=false`. O diário contém somente
tipo da ação, ID da tentativa, ferramenta e orçamento — nenhum
payload, token ou nome de jogador.

Tentativas repetidas são idempotentes e não gastam novo orçamento.
Uma execução simultânea durante verificação pendente recebe
`SIMULATOR_BUSY`. A rotina `dispatchLiveTool()` **sempre bloqueia**.

## O que não foi feito

- Não existe execução de observações no coletor real, nem autorização de
  usuário para executar ferramentas em jogo.
- O verificador de fixture não é um consentimento real nem comprova
  propriedade de uma experiência Roblox.
- Não há sensor de estado/GUI novo nem integração à base Luau atual.
- Duração de dez segundos é um **orçamento simulado**, não dez segundos
  de observação física.
- Nenhuma alteração foi feita ao gateway Render, coletor, bancos, APKs
  ou scripts Roblox publicados.

## Testar

Rodar `npm --prefix ai-core test` e
`npm --prefix ai-core run collector:demo`.

A CI também executa uma demonstração sintética, exigindo as duas
ferramentas e verificando que nenhuma delas teve execução real.
Os dados de origem são fixtures com campos de teste
maliciosos; o resultado não inclui esses campos.

## Próximas dependências

Para ferramentas ativas reais:
1. definir contrato de aprovação explícita por jogo, missão e duração,
   separado do mero recebimento de uma proposta;
2. autenticar servidor e sessão autorizados sem expor credenciais;
3. implementar as observações no coletor Luau sob allowlist e
   limites verificáveis no servidor;
4. registrar resultados reais saneados com trilha de auditoria e
   comparar evidências sem assumir causalidade.
