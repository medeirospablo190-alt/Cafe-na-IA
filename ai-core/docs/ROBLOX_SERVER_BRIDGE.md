# CAFEÍNA AI — Ponte do servidor Roblox (referência P3)

## O que está implementado

O contrato do módulo `src/roblox-server-verifier.mjs` permite que um
gateway **futuro e controlado pelo dono do jogo** valide um pedido
do servidor Roblox antes de chamar `src/menu-session-auth.mjs`.

A sequência prevista é:

1. Um **Script no ServerScriptService** faz POST HTTPS com
   `HttpService:RequestAsync()` e fornece `x-api-key` via
   `HttpService:GetSecret("CAFEINA_BRIDGE_SERVER_KEY")`.
2. O pedido traz `gameId`, `placeId`, `jobId` (`game.JobId`),
   `missionId`, timestamp (milissegundos) e nonce UUID.
3. O gateway verifica que o segredo corresponde à experiência
   configurada e que o pedido tem horário aceitável (30s para trás,
   5s para frente).
4. Um **registro confiável de jobs autorizado no servidor** precisa
   vincular {gameId, placeId, jobId, missionId} ao `runId` da sessão
   CAFEÍNA. Esse registro não pode aceitar IDs enviados por LocalScripts
   como prova.
5. O gateway registra o nonce de maneira **atômica e compartilhada**
   e rejeita qualquer reutilização ou indisponibilidade desse serviço.
6. Só então pode emitir credencial HMAC limitada à visualização de
   propostas e envio de recibos de não execução, por no máximo
   cinco minutos.

A chave de Roblox e a chave de assinatura HMAC são **diferentes**.
Ambas pertencem ao servidor. **Nenhuma** delas vai para Lua de cliente,
GitHub público, logs, modelo de IA ou dados do jogo.

## Referência Luau, deliberadamente inativa

O arquivo `roblox-reference/ServerBridgeReference.server.luau`
exemplifica o uso oficial de Secret Store e HTTP. Ele tem
`ENABLED = false`, URL vazia e ID de missão vazio. Não faz
requisições se for simplesmente copiado para o projeto.

O exemplo **não foi executado no Roblox Studio** e não deve ser
tratado como código pronto para produção. A documentação oficial
orienta ativar *Allow HTTP Requests* nas configurações da experiência.
Em ambiente de teste Studio, os segredos locais precisam ser
configurados separadamente.

Referências oficiais:
- https://create.roblox.com/docs/cloud-services/secrets
- https://create.roblox.com/docs/cloud-services/http-service
- https://create.roblox.com/docs/reference/engine/classes/HttpService

## O que ainda impede uso real

- Atestação Roblox automática de propriedade do jogo **não foi
  implementada**. Um segredo cadastrado comprova posse da chave,
  mas não sozinho a integridade do servidor ou a propriedade.
- O callback `resolveTrustedJob()` ainda usa um **mock de testes**.
  O cadastro da sessão/job deverá ser feito por fluxo confiável,
  com autorização do proprietário.
- `claimNonce()` precisa de armazenamento com operação atômica
  compartilhado entre instâncias do gateway. O armazenamento
  `createInMemoryNonceStore()` é estritamente para testes.
- Falta implantar HTTPS e rotas no gateway real com limite de
  taxa, prazos e capacidade de revogar sessões, além de credenciais
  configuradas fora do repositório.
- Falta o menu do Roblox real e uma experiência de teste autorizada
  que use essas rotas, sob autorização específica do proprietário.

Não existe executor remoto ou aprovação automática no contrato.
Propostas continuam com `approved=false` e `executable=false`.

## Testar sem tocar em produção

Os testes Node simulam o segredo, o registro do JobId e a proteção
contra repetição, além de exercitarem o ciclo HTTP por loopback.
Eles não podem demonstrar autenticidade Roblox nem validar Studio.
