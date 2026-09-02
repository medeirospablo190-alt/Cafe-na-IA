# GRUPO LUA KEYMASTER — V0.8 — EXCLUSÃO PROTEGIDA DE MENU

Status: **IMPLEMENTADO NA V0.8**

A V0.8 adiciona exclusão definitiva operacional de um menu administrado pelo Keymaster.

## Fluxo obrigatório

1. O operador abre o menu no Keymaster.
2. Escolhe `EXCLUIR MENU DEFINITIVAMENTE`.
3. O aplicativo mostra uma confirmação destrutiva explicando o impacto.
4. O Keymaster exige login e DEV KEY de uma conta `DEV` ativa.
5. A Control API cria uma autorização crítica com escopo exato:

```text
DELETE_MANAGED_MENU:<menuId>
```

6. A autorização dura no máximo 2 minutos e é de uso único.
7. O aplicativo envia essa autorização no `DELETE /v1/keymaster/menus/:id`.
8. O servidor consome a autorização antes de executar a exclusão.

Uma autorização criada para um menu não serve para excluir outro menu.

## Efeito server-side

A operação ocorre dentro de transação de banco:

- o menu passa para `status = DELETED`;
- `deleted_at` é preenchido automaticamente quando o status entra em `DELETED`;
- todas as chaves ainda não revogadas passam para `REVOKED`;
- `revoked_at` é preenchido nas chaves afetadas;
- todas as sessões ainda sem `revoked_at` são revogadas;
- o menu deixa de aparecer nas listagens do Keymaster;
- a URL pública deixa de resolver o menu;
- novas validações FREE/VIP deixam de encontrar o menu;
- não existe rota de restauração de um menu `DELETED`.

A migration `005_managed_menu_deleted_at.sql` cria o gatilho que registra `deleted_at` e também corrige registros antigos que por acaso já estejam em `DELETED` sem timestamp.

## Auditoria

A exclusão cria o evento:

```text
MENU_DELETED
```

O evento guarda somente metadados administrativos necessários, incluindo:

- `publicId`;
- nome do menu;
- quantidade de chaves revogadas;
- quantidade de sessões revogadas;
- sessão Keymaster responsável;
- conta DEV que autorizou a ação.

## Por que não apagar fisicamente todas as linhas

A V0.8 usa exclusão lógica definitiva em vez de apagar os registros do PostgreSQL. Isso preserva integridade referencial e trilha de auditoria. Para o produto, o menu está definitivamente removido: não pode ser restaurado pelo painel, não pode emitir novos acessos e não aparece nas consultas normais.

## Proteções

- somente uma sessão Keymaster válida pode iniciar o fluxo;
- somente conta `DEV` ativa pode autorizar;
- a autorização é vinculada ao `menuId`;
- expira em 2 minutos;
- só pode ser consumida uma vez;
- a exclusão revoga chaves e sessões na mesma transação;
- o token crítico e os tokens das sessões de menu não são exibidos após o fluxo.

## Escopo do App 1

Nenhuma área nova do Aplicativo 1 foi implementada nesta versão. O App 1 continua recebendo apenas a contraparte mínima necessária quando alguma função do Keymaster depender dela.
