# GRUPO LUA KEYMASTER — V0.4.0

Aplicativo 2 de maior privilégio do ecossistema GRUPO LUA, com cliente móvel Android/iPhone, API server-side, PostgreSQL e cliente mínimo do Aplicativo 1 para validar compatibilidade.

## Estrutura

```text
apps/keymaster        Aplicativo 2 Android/iPhone (Expo SDK 57)
apps/app1-probe       Cliente mínimo para testar logins criados pelo Keymaster
services/control-api  API server-side + PostgreSQL
packages/contracts    Constantes compartilhadas
```

## Princípio de segurança

O aplicativo pede; o servidor decide.

- role, status, validade, expiração, suspensão e revogação são decididos no servidor;
- o cliente não recebe hashes de credenciais nem segredos do servidor;
- a KEYMASTER ACCESS KEY original não é persistida no app;
- chaves FREE/VIP completas são exibidas somente no momento da criação;
- depois disso, a interface recebe somente um `key_hint` parcial;
- respostas administrativas usam `Cache-Control: no-store`;
- segredos reais ficam apenas em variáveis privadas do servidor.

## Segurança e autenticação do Keymaster

- campo Keymaster preparado para 16.384 caracteres;
- hash `scrypt` server-side;
- 3 erros consecutivos -> bloqueio persistente de 24h por dispositivo;
- regra de tentativas não depende do cliente;
- identificação por Android ID / IDFV + installation ID, protegida por HMAC no servidor;
- estrutura para Play Integrity / App Attest;
- sessão Keymaster revogável, validada novamente no servidor após biometria;
- token da sessão salvo somente em SecureStore/Keychain/Keystore.

## V0.3 — painel administrativo mobile

- dashboard com status do App 1;
- quantidade de ADM/DEV;
- quantidade de sessões ativas;
- eventos de auditoria das últimas 24h;
- barra de navegação inferior compacta;
- busca/filtros de contas;
- detalhes da conta;
- visualização e revogação de sessões;
- timeline de auditoria server-side;
- DEVs destacados em vermelho e Keymaster em roxo/preto.

## V0.4 — Menus e chaves FREE/VIP

A V0.4 adiciona uma camada server-side própria para registrar menus e controlar autorizações de acesso.

### Cadastro de menu

O Keymaster permite cadastrar:

- nome do menu;
- URL HTTPS do arquivo `.lua` no GitHub;
- `public_id` aleatório gerado pelo servidor;
- estado `ACTIVE` ou `SUSPENDED`;
- URL pública de acesso daquele menu.

A API aceita URLs `github.com/.../blob/.../*.lua` ou `raw.githubusercontent.com/.../*.lua`. Uma URL `github.com/blob` é normalizada para a equivalente `raw.githubusercontent.com`.

Suspender um menu invalida as sessões de acesso que ainda estiverem abertas. Restaurar o menu não restaura sessões antigas: um novo acesso precisa ser validado.

### FREE

- temporária;
- padrão do app: 24 horas;
- duração configurável em horas;
- limite atual da API: 365 dias por ajuste;
- validade calculada pelo relógio do servidor;
- pode ser suspensa e restaurada;
- pode ter a duração alterada;
- pode ser convertida para VIP/permanente mantendo o mesmo registro;
- pode ser revogada definitivamente.

### VIP

- permanente, sem expiração automática;
- pode ser suspensa/restaurada;
- pode ser revogada definitivamente.

### Suspender x revogar

Suspender é temporário. Ao suspender uma chave, as sessões de acesso abertas por ela são revogadas. A mesma chave pode ser liberada novamente.

Revogar é definitivo para aquele registro. Uma chave revogada não pode ser reativada.

### Armazenamento das chaves

A chave completa não é guardada em texto puro no banco. A API persiste:

- hash HMAC da chave;
- dica parcial (`key_hint`);
- tipo FREE/VIP;
- status;
- expiração quando aplicável;
- contador de usos e último uso;
- datas de suspensão/revogação.

A chave completa aparece uma única vez no aplicativo imediatamente após a geração.

## Fluxo de acesso a um menu

1. Keymaster cadastra o menu.
2. Servidor gera `public_id` e URL de acesso.
3. Keymaster gera uma chave FREE ou VIP.
4. Um cliente consulta a URL de acesso para descobrir os endpoints daquele menu.
5. O cliente envia `menuId` + chave para `/v1/menu-access/validate`.
6. Se a chave estiver válida, o servidor emite uma sessão curta de acesso, atualmente de no máximo 15 minutos.
7. Com essa sessão, `/v1/menu-access/:publicId/manifest` retorna os metadados autorizados do menu.
8. Suspensão/revogação do menu ou da chave impede novas validações e invalida sessões quando aplicável.

A sessão curta nunca pode ultrapassar o tempo restante de uma chave FREE.

## Limitação importante da fonte GitHub

Se o arquivo principal `.lua` estiver publicamente acessível por uma URL GitHub/raw conhecida, alguém que já conheça essa URL ainda pode tentar acessá-la diretamente. Portanto, esta camada protege distribuição, autorização, gerenciamento de chaves e fluxo de acesso, mas não transforma código cliente público em um segredo impossível de copiar.

Para proteção mais forte do conteúdo, a origem do código precisará deixar de ser uma URL pública direta e passar por uma camada de entrega controlada pelo servidor. Isso deve ser tratado separadamente antes de produção.

## Contas do Aplicativo 1

- criação de `ADM` e `DEV`;
- ADMIN APP KEY com 256 caracteres;
- DEV KEY com 600 caracteres;
- credenciais exibidas uma única vez;
- suspender/liberar conta;
- rotação de credencial revoga sessões abertas;
- exclusão individual exige reautenticação DEV e autorização server-side de uso único;
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

Exclusão global de dados/chaves e recuperação crítica continuam bloqueadas até o modelo de dados completo do App 1 existir. A exclusão definitiva de um menu também deve entrar em uma etapa DEV protegida antes de ser habilitada no painel; a V0.4 implementa cadastro, edição, suspensão e restauração.

## Banco de dados

Rode todas as migrations em ordem. A V0.4 adiciona:

```text
003_menus_keys.sql
004_menu_key_usage.sql
```

As tabelas principais são:

```text
managed_menus
menu_access_keys
menu_access_sessions
```

## Preparar o servidor

1. Crie um PostgreSQL e configure `DATABASE_URL`.
2. Copie `services/control-api/.env.example` para `.env` no ambiente do servidor.
3. Configure `PUBLIC_BASE_URL` com a URL HTTPS pública canônica da Control API.
4. Gere `SESSION_PEPPER` e `DEVICE_FINGERPRINT_PEPPER` fortes e diferentes.
5. Gere o hash da chave Keymaster sem copiá-la para o código:

```bash
cd services/control-api
npm run hash:keymaster -- /caminho/KEYMASTER_ACCESS_KEY.txt
```

6. Coloque somente o `KEYMASTER_ACCESS_HASH` resultante nas variáveis privadas do servidor.
7. Rode as migrations:

```bash
npm run api:migrate
```

8. Inicie a API:

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
