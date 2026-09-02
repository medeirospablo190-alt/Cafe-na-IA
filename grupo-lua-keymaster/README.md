# GRUPO LUA KEYMASTER — V0.8.0

Aplicativo 2 de maior privilégio do ecossistema GRUPO LUA, com cliente móvel Android/iPhone, API server-side, PostgreSQL e cliente mínimo do Aplicativo 1 para validar compatibilidade.

## Estrutura

```text
apps/keymaster        Aplicativo 2 Android/iPhone (Expo SDK 57)
apps/app1-probe       Cliente mínimo para testar logins criados pelo Keymaster
services/control-api  API server-side + PostgreSQL
packages/contracts    Constantes e contratos compartilhados
docs                  Requisitos e decisões de arquitetura
```

## Princípio de segurança

O aplicativo pede; o servidor decide.

- role, status, validade, expiração, suspensão e revogação são decididos no servidor;
- o cliente não recebe hashes de credenciais nem segredos do servidor;
- a KEYMASTER ACCESS KEY original não é persistida no app;
- chaves FREE/VIP completas são exibidas somente no momento da criação;
- depois disso, a interface recebe somente um `key_hint` parcial;
- tokens secretos de sessões de menu nunca são exibidos no painel administrativo;
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

## V0.5 — operação mobile do Keymaster

A V0.5 continua focada somente no Aplicativo 2. Nenhuma área completa de Social/Chats/Arquivos/Feed do Aplicativo 1 foi iniciada.

### Tela inicial

O dashboard móvel passa a mostrar também:

- total de menus cadastrados;
- menus ativos;
- total agregado de chaves FREE;
- total agregado de chaves VIP;
- acessos/validações de menus acumulados no mês.

As métricas de contas, sessões do App 1, manutenção e auditoria continuam presentes.

### Administração de menus

Os cartões de menu foram compactados para celular e mostram de forma mais direta:

- FREE ativas;
- VIP ativas;
- acessos ativos agora;
- acessos registrados no mês;
- URL de acesso;
- estado ativo/suspenso.

Suspender um menu pelo aplicativo exige uma confirmação visual antes da chamada ao servidor, pois a operação revoga sessões de acesso abertas.

### Administração de chaves

Ao abrir um menu, o Keymaster mostra resumo de:

- total de chaves;
- chaves atualmente utilizáveis;
- soma do contador de usos.

Também foram adicionados busca local por `key_hint` ou observação e filtros rápidos:

```text
TODAS
FREE
VIP
ATIVAS
SUSPENSAS
EXPIRADAS
REVOGADAS
```

Cada chave destaca no painel móvel tipo, estado, expiração, observação, contador de usos e data/hora do último uso.

## V0.6 — contrato mínimo App 1 ↔ Keymaster

A V0.6 formaliza somente o necessário para que as contas criadas pelo Keymaster permaneçam compatíveis com o futuro Aplicativo 1.

- contrato compartilhado de roles `ADM` e `DEV`;
- ADMIN APP KEY com 256 caracteres;
- DEV KEY com 600 caracteres;
- testes automáticos verificam que o gerador real continua obedecendo esses tamanhos;
- permissões-base compartilhadas entre os clientes;
- `app1.social.pin-post` reservado somente a DEV, sem implementar o Social;
- App 1 Probe testa login, sessão, role, status e revogação, mas continua sendo apenas uma sonda de compatibilidade;
- Feed, Chats, Arquivos, perfis e notificações do App 1 continuam adiados.

O contrato detalhado fica em `docs/app1-keymaster-contract.md`.

## V0.7 — controle de sessões de acesso dos menus

A V0.7 adiciona ao Keymaster administração direta das sessões temporárias emitidas após uma chave FREE/VIP ser validada.

Para cada sessão recente o painel mostra tipo da chave, `key_hint`, observação, cliente, criação, expiração, último sinal e estado ativa/revogada/expirada. O token secreto usado pelo cliente não é retornado ao Keymaster.

Ações disponíveis:

- atualizar e pesquisar sessões;
- filtrar por todas / ativas / encerradas;
- revogar uma sessão específica;
- revogar todas as sessões ainda ativas de um menu.

Revogar sessões não revoga automaticamente a chave FREE/VIP de origem. Para impedir novas autenticações, suspenda/revogue a chave ou suspenda o menu.

As revogações ficam na auditoria como:

```text
MENU_ACCESS_SESSION_REVOKED
MENU_ACCESS_SESSIONS_REVOKED_ALL
```

## V0.8 — exclusão protegida de menu

A V0.8 adiciona exclusão definitiva operacional de um menu, protegida pelo mesmo sistema de *step-up authentication* usado nas ações críticas do Keymaster.

Fluxo:

1. sessão Keymaster válida;
2. confirmação destrutiva no painel;
3. reautenticação com uma conta `DEV` ativa;
4. autorização server-side de uso único com escopo `DELETE_MANAGED_MENU:<menuId>`;
5. validade máxima de 2 minutos;
6. `DELETE /v1/keymaster/menus/:id` consome a autorização;
7. servidor revoga sessões e chaves associadas e marca o menu como `DELETED` em transação.

Uma autorização emitida para um menu não pode excluir outro. O painel não possui restauração para `DELETED`, a URL pública deixa de resolver o menu e novas validações FREE/VIP deixam de funcionar.

A exclusão é lógica e definitiva para o produto: os registros mínimos permanecem no PostgreSQL para integridade referencial e auditoria. A migration `005_managed_menu_deleted_at.sql` garante o preenchimento de `deleted_at` quando um menu entra em `DELETED`.

Evento principal de auditoria:

```text
MENU_DELETED
```

Detalhes completos em `docs/keymaster-v0.8-menu-deletion.md`.

## Requisito salvo do Aplicativo 1 — ainda não implementado

Antes de continuar o desenvolvimento completo do App 1, uma regra da área Social foi registrada em `docs/app1-social-requirements.md`.

O documento registra que somente DEV poderá fixar/desafixar publicações, que a publicação fixada mais recentemente deve aparecer no topo do feed com destaque/aura vermelha e que os outros administradores devem receber uma notificação quando um DEV fixar uma publicação.

**Esse requisito está apenas salvo. O desenvolvimento atual continua no Aplicativo 2 — Keymaster.**

## Fluxo de acesso a um menu

1. Keymaster cadastra o menu.
2. Servidor gera `public_id` e URL de acesso.
3. Keymaster gera uma chave FREE ou VIP.
4. Um cliente consulta a URL de acesso para descobrir os endpoints daquele menu.
5. O cliente envia `menuId` + chave para `/v1/menu-access/validate`.
6. Se a chave estiver válida, o servidor emite uma sessão curta de acesso, atualmente de no máximo 15 minutos.
7. Com essa sessão, `/v1/menu-access/:publicId/manifest` retorna os metadados autorizados do menu.
8. O Keymaster pode encerrar a sessão específica ou todas as sessões ativas do menu.
9. Suspensão/revogação do menu ou da chave impede novas validações e invalida sessões quando aplicável.

A sessão curta nunca pode ultrapassar o tempo restante de uma chave FREE.

## Limitação importante da fonte GitHub

Se o arquivo principal `.lua` estiver publicamente acessível por uma URL GitHub/raw conhecida, alguém que já conheça essa URL ainda pode acessá-la diretamente. Esta camada protege distribuição, autorização, gerenciamento de chaves e fluxo de acesso, mas não transforma código cliente público em um segredo impossível de copiar.

Para proteção mais forte do conteúdo, a origem do código precisará deixar de ser uma URL pública direta e passar por uma camada de entrega controlada pelo servidor.

## Contas do Aplicativo 1

- criação de `ADM` e `DEV`;
- ADMIN APP KEY com 256 caracteres;
- DEV KEY com 600 caracteres;
- credenciais exibidas uma única vez;
- suspender/liberar conta;
- rotação de credencial revoga sessões abertas;
- exclusão individual exige reautenticação DEV e autorização server-side de uso único;
- sessões podem ser encerradas pelo Keymaster e a ação fica na auditoria;
- App 1 Probe autentica as mesmas contas criadas pelo Keymaster.

## Ações críticas

A camada de *step-up authentication* funciona assim:

1. sessão Keymaster válida;
2. reautenticação com uma conta `DEV` ativa;
3. servidor gera uma autorização aleatória de uso único, escopada à ação/alvo e com validade de 2 minutos;
4. a autorização é consumida uma única vez e não pode ser reutilizada.

Já implementado:

- ativar manutenção do App 1;
- encerrar manutenção do App 1;
- bloquear login/uso de sessões do App 1 durante manutenção;
- solicitar reinício por webhook privado quando configurado;
- excluir uma conta individual somente após reautenticação DEV;
- excluir definitivamente um menu somente após reautenticação DEV;
- auditoria das autorizações e execuções críticas.

Exclusão global de dados/chaves e recuperação crítica continuam bloqueadas até o modelo de dados completo do App 1 existir.

## Banco de dados

Rode todas as migrations em ordem. A camada de menus usa:

```text
003_menus_keys.sql
004_menu_key_usage.sql
005_managed_menu_deleted_at.sql
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
