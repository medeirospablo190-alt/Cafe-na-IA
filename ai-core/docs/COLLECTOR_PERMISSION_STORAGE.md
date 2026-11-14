# Registro persistente de permissões sintéticas — Etapa P4

## Armazenamento

O novo módulo \`src/github-collector-permissions.mjs\` possui um contrato
de **um pedido por missão** na branch isolada \`cafeina-ai-knowledge\`:
\`ai-core/collector-permissions/<gameId>/<missionId>.json\`.

O arquivo é um envelope validado com:
- \`revision: 0\`, \`PENDING_REVIEW\`, pedido saneado e \`review: null\`;
- \`revision: 1\`, \`REVIEWED\`, pedido original inalterado e decisão final
  \`DENIED\` ou \`SIMULATION_ALLOWED\`, ambas estritamente offline.

A gravação usa GitHub Contents API com SHA otimista e tentativas limitadas
após conflito. É \`dryRun=true\` por padrão; a escrita real exige
token GitHub do runner/servidor. Uma segunda decisão diferente é recusada,
mesmo se a primeira permitir somente simulação. Repetir a mesma decisão
é idempotente. O documento é validado integralmente em cada leitura.

O registro **não prova que um usuário real autorizou algo**: validação
de conteúdo e integridade do GitHub não equivalem a identidade de um
operador. Só um serviço confiável externo, ainda não implementado,
poderia autenticar uma decisão real. Mesmo assim, este contrato não permite
executar ferramentas Roblox.

## Teste no GitHub real

O workflow \`.github/workflows/cafeina-ai-permission-roundtrip.yml\`
executou três runners independentes, com dados exclusivamente sintéticos:

1. Criou proposta e pedido de permissão para gameId=101 e placeId=202.
2. Usou um operador **simulado** para registrar a decisão \`DENIED\`.
3. Recuperou a mesma recusa em outro runner com \`contents: read\`.

Teste confirmado:
https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41386181653

Todos os registros foram salvos em branch de experimentos. Não houve
alteração de Roblox, Render, coletor ou experiências, nem aprovação de
ferramentas ao vivo.

## Modelo da futura interface

\`src/collector-permission-view.mjs\` transforma o envelope válido em
um modelo de **exibição** para uma futura tela, sem callbacks nem
comandos de execução. Mostra ferramenta, finalidade, número máximo de
pré-visualizações, orçamento, prazo e decisão.

Em estado pendente oferece apenas os rótulos de teste
\`DENIED\` e \`SIMULATION_ALLOWED\` como opções visuais não conectadas.
Quando expirado ou concluído, não apresenta opções de revisão.
O modelo sempre declara \`realApprovalAvailable=false\`,
\`canExecuteRobloxTools=false\` e \`displayOnly=true\`.

Essa tela ainda **não foi criada nem instalada no menu Roblox**. Falta
autenticação do usuário, vínculo confiável à experiência, interface real,
revogação e auditoria durável para uso além de testes.

## Privacidade e retenção

Os arquivos experimentais contêm somente IDs sintéticos, enumerações,
instantes e hashes de propostas saneadas, não segredos GitHub, IDs de
jogadores ou argumentos de remotes. Os documentos são legíveis em um
repositório público caso a branch seja pública.

É necessário aprovar política de expurgo e considerar o histórico Git
antes de armazenar qualquer informação que deixe de ser estritamente
sintética. **Não compartilhar credenciais nem dados de jogadores.**
