# GRUPO LUA — Control API no Render

Este documento cobre somente a **Control API dedicada** dos aplicativos. O portal `https://cafe-na-ia.onrender.com` continua sendo exclusivamente o portal de downloads e nunca deve receber credenciais ADM/DEV ou a chave do Keymaster.

## Blueprint

Arquivo: `render-control-api.yaml`

Ele cria:

- Web Service `grupo-lua-control-api`;
- Postgres `grupo-lua-control-db` na mesma região;
- rede de banco sem acesso público (`ipAllowList: []`);
- `PUBLIC_BASE_URL` derivada automaticamente de `RENDER_EXTERNAL_URL`;
- `DATABASE_URL` derivada do connection string interno do Postgres;
- migrations antes de cada deploy;
- verificação `production:check` antes das migrations e em todo início do servidor;
- health check em `/v1/health`;
- auto-deploy inicialmente desligado.

## Por que os planos não são `free`

O fluxo de produção usa `preDeployCommand` para executar migrations antes da troca de versão. No Render, pre-deploy é recurso de Web Service pago. Além disso, Postgres Free expira e não é apropriado para dados persistentes de autenticação, dispositivos e auditoria.

O Blueprint usa os menores planos pagos flexíveis definidos atualmente:

- Web: `0.5c-512mb`;
- Postgres: `0.1c-256mb`.

Antes de sincronizar o Blueprint no Render, confirme preço e cobrança diretamente no painel do provedor.

## Único segredo que precisa ser informado no primeiro sync

`KEYMASTER_ACCESS_HASH`

Não use a chave Keymaster original. Gere apenas o verificador scrypt com o script do projeto e cole o hash no campo privado que o Render solicitar.

Os peppers de sessão e dispositivo usam `generateValue: true`, portanto o Render gera valores aleatórios e os mantém fora do GitHub.

## Ordem do primeiro deploy

1. No Render, criar um novo Blueprint usando este repositório.
2. Escolher `render-control-api.yaml` como Blueprint.
3. Conferir região e planos antes de confirmar qualquer cobrança.
4. Quando solicitado, informar somente o `KEYMASTER_ACCESS_HASH` real.
5. Criar/sincronizar os recursos.
6. Aguardar o pre-deploy executar `production:check` e `migrate`.
7. Confirmar que `/v1/health` retorna HTTP 200 e `service: GRUPO_LUA_CONTROL_API`.
8. Copiar a URL HTTPS real da Control API.
9. Usar essa URL em `EXPO_PUBLIC_GRUPO_LUA_API_URL` nas builds App 1 e Keymaster.
10. Testar Keymaster, criação de ADM, primeiro login App 1, onboarding, sessão de 24h, bloqueio e autorização de segundo dispositivo.

## App Integrity

O Blueprint começa com `APP_INTEGRITY_MODE=report`. Isso permite integrar e observar o provedor de integridade sem bloquear usuários por uma configuração ainda incompleta.

Antes da liberação final, o objetivo é configurar um verificador server-side real (Play Integrity no Android e mecanismo equivalente no iOS) e somente então mudar para `APP_INTEGRITY_MODE=enforce`.

`production:check` recusa `enforce` sem `APP_INTEGRITY_VERIFY_URL`.

## Ações externas críticas

`CRITICAL_ACTIONS_ENABLED=false` permanece por padrão. Manutenção interna e operações protegidas continuam disponíveis, mas o reinício externo via webhook fica desligado até haver um endpoint HTTPS privado configurado conscientemente.

## Banco

No Render, a API usa o `connectionString` interno do Postgres, portanto `DATABASE_SSL=false` é intencional para essa conexão privada na mesma região.

O banco não recebe allowlist pública no Blueprint. Ferramentas externas não devem acessar o banco de produção diretamente sem uma decisão explícita de operação e segurança.

## Proteções contra configuração errada

`npm run production:check` falha se:

- faltar `DATABASE_URL`;
- faltar `KEYMASTER_ACCESS_HASH`;
- faltar algum pepper;
- `PUBLIC_BASE_URL` não for HTTPS;
- `PUBLIC_BASE_URL` apontar para `cafe-na-ia.onrender.com`;
- `PUBLIC_BASE_URL` usar `.invalid`, localhost ou loopback;
- o hash Keymaster não tiver o formato scrypt esperado;
- algum pepper for curto demais;
- `APP_INTEGRITY_MODE` for inválido;
- `enforce` estiver ativo sem verificador;
- ações externas estiverem habilitadas sem webhook HTTPS.

O CI também testa explicitamente que o portal de downloads é rejeitado como Control API.

## O que nunca entra no GitHub

- chave Keymaster original;
- credenciais ADM/DEV reais;
- `DATABASE_URL` real;
- peppers reais;
- token do verificador de integridade;
- webhook/token de reinício;
- chaves privadas de assinatura Android/iOS;
- senhas reais do portal de downloads.
