# CAFEÍNA — comunicação menu ↔ servidor Roblox ↔ gateway ↔ GitHub

**Escopo atual:** transporte de propostas de observação e recibos de **não execução** na experiência de propriedade ou autorizada. Não permite executar Luau recebido, descobrir remotes privados, contornar proteções ou acessar código-fonte interno de terceiros.

## Arquitetura

1. O menu móvel `ExecutorMenu.client.luau` usa apenas o RemoteFunction **CAFEINA_MENU_REMOTE** quando ele existe na própria experiência. O menu também continua a funcionar offline, sem o servidor.
2. `OwnerMenuBridge.server.luau` é instalado em **ServerScriptService pelo proprietário**, com `ENABLED=false` por padrão e allow-list de UserIds. Nenhum outro jogador recebe acesso. Um Secret da experiência é usado **somente no servidor**.
3. O script envia `POST /v1/roblox/menu` ao gateway HTTPS configurado pelo proprietário. Dados enviados: `schemaVersion, operation, gameId, placeId, jobId, runId, missionId`. Não envia conteúdo de jogador, remotes brutos ou código.
4. `src/owner-menu-bridge.mjs` autentica a chave, exige a correspondência exata de **uma experiência, sessão, missão e JobId pré-cadastrados** e só aceita `POLL`, `ACK`, `DECLINE` e `NO_EXECUTION`. Rejeita requisições excessivas e simultâneas.
5. O gateway lê uma proposta já criada em `cafeina-ai-knowledge/ai-core/mission-queue/<gameId>/<missionId>.json`, valida sua identidade, validade e bloqueio de execução, e grava os recibos em `ai-core/menu-receipts/<gameId>/<missionId>.json` usando SHA, revisões e os adaptadores existentes.
6. O menu recebe somente uma projeção: ID da missão, ferramenta passiva, duração e validade. O retorno não contém token do GitHub, chave de servidor, evidência bruta ou script.

Fluxo: **menu (cliente não confiável) → RemoteFunction com UserId validado → Script servidor Roblox → HTTPS → gateway Node → API GitHub (branch de conhecimento)**. Não há conexão HTTP direta do executor com o GitHub.

## O que funciona agora

- Código de ponta a ponta criado, testes de transporte/armazenamento usando API GitHub **simulada**, e validação por CI.
- A operação de consulta **precisa persistir DELIVERED no GitHub antes de responder**; ACK e DECLINE/NO_EXECUTION também exigem escrita durável. Falhas resultam em erro, não em falso sucesso.
- Propostas permanecem `approved=false`, `executable=false`; a interface não concede permissão para coleta real.
- O botão Diagnóstico da interface mostra a presença da ponte e permite solicitar `STATUS` ao servidor Roblox, sem chamar o gateway.

## Trabalhador de análise no GitHub (sem processamento no celular)

O módulo `src/mission-worker.mjs` aceita um **relatório V3 já saneado**,
confere a missão e gera um plano de observação com prazo de 10 minutos.
O comando `src/mission-worker-cli.mjs` lê o relatório de disco e grava uma
proposta JSON limitada, sem interação com Roblox:

```bash
node ai-core/src/mission-worker-cli.mjs /tmp/relatorio-v3-saneado.json /tmp/proposta.json
```

**Por padrão, é DRY_RUN, sem rede e sem publicação.** A publicação pela API
GitHub requer explicitamente `CAFEINA_WORKER_PUBLISH=true`,
`CAFEINA_OWNER_APPROVED=yes`, `CAFEINA_AUTHORIZED_GAME_ID` e
`CAFEINA_AUTHORIZED_RUN_ID` correspondentes à missão, além de
`GITHUB_REPOSITORY` e `GITHUB_TOKEN` do servidor. Sem isso,
recusa publicar. O pipeline de CI produz uma prévia de missão de uma
sessão V3 já existente, mas não salva missões na branch de conhecimento.

Esse trabalhador **não reconstrói código, não coleta do jogo e não executa
comandos**: ainda falta integrar especialistas, ferramentas passivas
autorizadas, comparações do REA e validação de código Luau original.
O usuário precisa autorizar especificamente uma publicação/implantação real.

## Configuração necessária para um teste real na SUA experiência

**1. GitHub:** criar ou selecionar uma proposta de observação válida e ainda não expirada na branch `cafeina-ai-knowledge`, usando o pipeline V3 existente e `publishGithubMenuProposal` (a escrita é opt-in). Anotar `gameId`, `placeId`, `runId` e `missionId`. Não colocar dados brutos de jogadores no GitHub.

**2. Gateway (ambiente isolado):** iniciar com Node 22+ e as variáveis abaixo. `GITHUB_TOKEN` precisa de acesso mínimo de leitura/escrita Contents no repositório de teste, nunca no cliente Roblox. Usar HTTPS terminando em proxy confiável, com limite de taxa, proteção contra abuso e armazenamento seguro dos segredos.

```text
CAFEINA_BRIDGE_ENABLE=true
GITHUB_REPOSITORY=medeirospablo190-alt/Cafe-na-IA
GITHUB_TOKEN=<segredo somente no servidor>
CAFEINA_ROBLOX_SERVER_KEY=<segredo aleatório de pelo menos 32 caracteres>
CAFEINA_GAME_ID=<gameId da proposta>
CAFEINA_PLACE_ID=<placeId da proposta>
CAFEINA_RUN_ID=<runId da proposta>
CAFEINA_MISSION_ID=<missionId da proposta>
CAFEINA_JOB_ID=<JobId exato do servidor de teste>
CAFEINA_LISTEN_HOST=127.0.0.1
PORT=3000
```

Executar: `node ai-core/src/owner-menu-bridge-cli.mjs`. Para um proxy externo, o container precisará ouvir na interface apropriada **somente quando protegido por TLS e controles de acesso**. Não expor porta HTTP pura à internet.

**3. Roblox Studio:** em uma experiência sua, habilitar *Allow HTTP Requests*, configurar o Secret Store com o mesmo `CAFEINA_ROBLOX_SERVER_KEY`, copiar `OwnerMenuBridge.server.luau` para ServerScriptService, configurar `GATEWAY_URL` HTTPS, `RUN_ID`, `MISSION_ID`, e `OWNER_USER_IDS`. Alterar `ENABLED=true` **apenas após** a configuração e autorização. O RemoteFunction é criado pelo script no ReplicatedStorage. A sessão JobId muda quando o servidor reinicia; para este protótipo, registrar o JobId do servidor de teste no gateway por um operador confiável e reiniciar/reconfigurar quando necessário.

**4. Menu:** execute a versão v0.3 no dispositivo no mesmo jogo. Em Missões, toque em *Consultar missão autorizada* → *Confirmar recebimento* → *Recusar* ou *Registrar não execução*. Confirmar que o recibo chegou ao GitHub na branch de conhecimento. Nenhuma operação efetua observação ativa ou modifica o jogo.

**5. CI sem credenciais:** `npm --prefix ai-core run check:owner-bridge` e `npm --prefix ai-core test`.

## Limitações de segurança e engenharia reversa

- Esta ponte é **infraestrutura de comunicação**, não um sistema completo de engenharia reversa. O sistema atual analisa V3, formula hipóteses e planos; ainda falta validar observações reais de uma experiência autorizada e produzir/testar código Luau original.
- Não é possível instalar `ServerScriptService` em experiências de terceiros sem acesso de desenvolvedor. A existência de um executor cliente não prova propriedade do jogo nem dá acesso ao código interno de servidor.
- A posse de um Secret da experiência + allow-list de JobId é um controle operacional, **não atestação criptográfica da plataforma Roblox**. Antes de produção: registro e revogação de Jobs em armazenamento durável, autenticação de proprietário, armazenamento de nonce anti-replay entre réplicas, monitoramento, rate limits distribuídos, política de retenção e revisão do escopo do token GitHub.
- O formato persistido de entregas ainda está nomeado `SIMULATOR_ONLY`: é uma prova controlada de transporte e recibos de não execução, **não uma autorização de ferramentas**.
- O gateway não publica propostas nem despacha tarefas de IA sozinho: uma proposta válida precisa ser preparada pelo pipeline GitHub/CAFEÍNA existente. Nem GitHub Actions nem esta ponte oferecem um daemon de inferência 24/7.

Referências Roblox: https://create.roblox.com/docs/cloud-services/http-service ; https://create.roblox.com/docs/cloud-services/secrets ; https://create.roblox.com/docs/scripting/security/client-server-boundary
