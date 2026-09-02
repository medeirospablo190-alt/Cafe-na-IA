# GRUPO LUA KEYMASTER — V0.3.0

Aplicativo 2 de maior privilégio do ecossistema GRUPO LUA, com cliente móvel Android/iPhone, API server-side e cliente mínimo do Aplicativo 1 para validar compatibilidade desde o início.

## Estrutura

```text
apps/keymaster        Aplicativo 2 Android/iPhone (Expo SDK 57)
apps/app1-probe       Cliente mínimo para testar logins criados pelo Keymaster
services/control-api  API server-side + PostgreSQL
packages/contracts    Constantes compartilhadas
```

## Segurança e autenticação

- campo Keymaster preparado para 16.384 caracteres;
- chave mestre não é persistida no app;
- hash `scrypt` server-side;
- 3 erros consecutivos -> bloqueio persistente de 24h por dispositivo;
- regra de tentativas não depende do cliente;
- identificação por Android ID / IDFV + installation ID, protegida por HMAC no servidor;
- estrutura para Play Integrity / App Attest;
- sessão Keymaster revogável, validada novamente no servidor após biometria;
- token da sessão salvo somente em SecureStore/Keychain/Keystore;
- respostas administrativas usam `Cache-Control: no-store`;
- ações destrutivas continuam dependendo do servidor.

## V0.3 — painel administrativo mobile

A V0.3 aproxima o Keymaster do layout mobile preto/minimalista definido nos mockups e adiciona administração operacional real:

- dashboard com status do App 1;
- quantidade de ADM/DEV;
- quantidade de sessões ativas;
- eventos de auditoria das últimas 24h;
- barra de navegação inferior compacta;
- busca de contas por login;
- filtros ADM/DEV e ativa/suspensa;
- detalhes da conta;
- visualização de sessões do App 1;
- revogação individual de sessão;
- revogação de todas as sessões ativas da conta;
- timeline de auditoria server-side com paginação;
- DEVs destacados em vermelho e Keymaster em roxo/preto.

Busca, filtros, contagens e auditoria são consultados em endpoints autenticados. O cliente não recebe hashes de credenciais, tokens persistidos no banco nem segredos do servidor.

## Contas do Aplicativo 1

- criação de `ADM` e `DEV`;
- ADMIN APP KEY com 256 caracteres;
- DEV KEY com 600 caracteres;
- credenciais exibidas uma única vez;
- suspender/liberar conta;
- rotação de credencial revoga sessões abertas;
- exclusão individual exige **reautenticação DEV** e autorização server-side de uso único;
- sessões podem ser encerradas pelo Keymaster e a ação fica na auditoria;
- App 1 probe autentica as mesmas contas criadas pelo Keymaster.

## Ações críticas

A camada de *step-up authentication* funciona assim:

1. sessão Keymaster válida;
2. reautenticação com uma conta `DEV` ativa;
3. servidor gera uma autorização aleatória de uso único, escopada à ação e com validade de 2 minutos;
4. a autorização é consumida uma única vez e não pode ser reutilizada.

Já implementado:

- ativar manutenção do App 1;
- encerrar manutenção do App 1;
- bloquear login/uso de sessões do App 1 durante manutenção;
- solicitar reinício por webhook privado quando configurado;
- excluir uma conta individual somente após reautenticação DEV;
- auditoria das autorizações e execuções críticas.

A exclusão global de dados/chaves e recuperação crítica permanecem bloqueadas até que as tabelas do App 1 completo (Social, Chats, Arquivos, menus e FREE/VIP) existam. Isso evita implementar exclusões genéricas sem escopo de dados definido.

## Preparar o servidor

1. Crie um PostgreSQL e configure `DATABASE_URL`.
2. Copie `services/control-api/.env.example` para `.env` no ambiente do servidor.
3. Gere `SESSION_PEPPER` e `DEVICE_FINGERPRINT_PEPPER` fortes e diferentes.
4. Gere o hash da sua chave de desenvolvimento/produção sem copiá-la para o código:

```bash
cd services/control-api
npm run hash:keymaster -- /caminho/KEYMASTER_ACCESS_KEY.txt
```

5. Coloque somente o `KEYMASTER_ACCESS_HASH` resultante nas variáveis privadas do servidor.
6. Rode as migrations:

```bash
npm run api:migrate
```

7. Inicie a API:

```bash
npm run api:start
```

## Reinício do App 1

O Keymaster não contém token de provedor. Configure no servidor:

```text
CRITICAL_ACTIONS_ENABLED=true
APP1_RESTART_WEBHOOK=https://...
APP1_CONTROL_WEBHOOK_TOKEN=...
```

Sem isso, a API recusa o reinício com erro de configuração em vez de fingir que reiniciou.

## Aplicativo 2

```bash
npm install
cd apps/keymaster
npx expo install --fix
npm run typecheck
npx expo run:android
# ou
npx expo run:ios
```

Defina `EXPO_PUBLIC_GRUPO_LUA_API_URL` para a URL da API, ou altere `extra.apiUrl` em `app.json`.

## Integridade de dispositivo

O `.env.example` usa `report` para o primeiro boot não ficar bloqueado antes da configuração do verificador. Em produção, depois de configurar Play Integrity/App Attest e o verificador server-side, altere para:

```text
APP_INTEGRITY_MODE=enforce
```

Nunca trate apenas o `deviceId` enviado pelo cliente como prova suficiente.

## Não colocar no GitHub

- KEYMASTER ACCESS KEY original;
- SESSION_PEPPER;
- DEVICE_FINGERPRINT_PEPPER;
- tokens Google/Apple;
- `APP1_CONTROL_WEBHOOK_TOKEN`;
- credenciais de banco;
- qualquer arquivo `.env` real.
