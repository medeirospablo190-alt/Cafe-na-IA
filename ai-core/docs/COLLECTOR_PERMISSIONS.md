# Revisão de permissões do coletor (somente simulação P4)

## Fluxo implementado

1. O agente cria um **pedido pendente** (`cafeina_collector_permission_request`) a partir de proposta saneada de `watch_state` ou `observe_gui`.
2. O contrato exige gameId/placeId/runId, hash completo da proposta, motivo de enum, máximo de duas prévias de 10 segundos e prazo até cinco minutos.
3. Um verificador confiável **de teste** fornece prova de operador sintético, separada de qualquer ACK do menu.
4. O sistema registra `DENIED` ou `SIMULATION_ALLOWED`, sempre com escopo `SYNTHETIC_PREVIEW_ONLY`. A decisão tem hash da solicitação, identidade e prazo.
5. Cada prévia exige nova confirmação por um registro de revisão de teste independente. Recusa, expiração, JSON alterado e ausência do registro bloqueiam a prévia.
6. Auditoria registra apenas IDs da missão, solicitação e revisão, ferramenta, decisão, horários e flags de não execução; nunca prova do operador nem dados de jogadores.

## Fronteira de segurança

**Não há consentimento real de usuário ou proprietário**, autenticação de operador real ou execução do coletor. `RECEIVED` do menu é só ACK, não autorização. A simulação pode liberar uma prévia offline de metadados já saneados, mas não aprova ferramenta ao vivo. Não há interação com Render, Roblox, APK ou coleta real.

O sistema precisa de interface real de consentimento, verificação de propriedade da experiência, revogação, histórico persistente e testes em ambiente autorizado antes de qualquer execução de ferramenta.

## Testar

`npm --prefix ai-core run collector:permissions-demo` verifica pedido, aprovação **sintética**, recusa, consulta da decisão a um registro de teste e auditoria para ambas as ferramentas. A CI exige zero execuções reais e ausência dos campos sensíveis nas saídas.

## Persistência em branch e modelo de exibição

\`src/github-collector-permissions.mjs\` grava, opcionalmente, somente
metadados de **permissões sintéticas** com um pedido imutável e uma decisão
final versionada. A gravação real do caso \`DENIED\` foi comprovada em
três runners GitHub, incluindo recuperação independente:
https://github.com/medeirospablo190-alt/Cafe-na-IA/actions/runs/41386181653

\`src/collector-permission-view.mjs\` fornece um modelo de exibição
seguro, sem ações, para a futura tela. Isso não é uma UI Roblox
funcionando e não concede consentimento do usuário. Consulte
\`docs/COLLECTOR_PERMISSION_STORAGE.md\`.
