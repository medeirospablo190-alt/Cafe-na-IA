# GRUPO LUA — CONTRATO APP 1 ↔ KEYMASTER

Status: **IMPLEMENTAÇÃO MÍNIMA ATIVA / APP 1 COMPLETO AINDA ADIADO**

Este documento define somente a parte do Aplicativo 1 que precisa existir enquanto o desenvolvimento principal continua focado no Aplicativo 2 — Keymaster.

## Regra de escopo

O App 1 só deve receber implementação antecipada quando uma função já existente do Keymaster precisar de uma contraparte para funcionar ou ser validada.

Exemplos permitidos nesta fase:

- autenticar contas ADM/DEV criadas pelo Keymaster;
- validar sessão emitida pelo servidor;
- reconhecer role e status retornados pelo servidor;
- respeitar suspensão, exclusão, manutenção e revogação de sessão;
- compartilhar contratos de role/permissão necessários para evitar incompatibilidade;
- reservar permissões já aprovadas para recursos futuros, sem construir o recurso completo.

Não iniciar ainda:

- Feed Social completo;
- Chats;
- Arquivos;
- perfis completos;
- fotos/vídeos;
- notificações completas;
- demais telas finais do App 1.

## Credenciais emitidas pelo Keymaster

O contrato atual é:

```text
ADM -> 256 caracteres
DEV -> 600 caracteres
```

A credencial completa é criada pelo servidor e exibida uma única vez pelo Keymaster. O App 1 envia a credencial para validação, mas não decide se ela é válida.

Os testes da Control API verificam automaticamente se o gerador continua respeitando os tamanhos definidos no pacote compartilhado `@grupo-lua/contracts`.

## Sessão do App 1

Depois de um login válido, o servidor emite uma sessão. O cliente pode persistir o token em armazenamento seguro e deve revalidar a sessão pelo endpoint `/v1/app1/me`.

O App 1 não deve considerar um token local como prova suficiente de autorização. Uma sessão pode deixar de ser válida porque:

- expirou;
- foi revogada pelo Keymaster;
- a conta foi suspensa;
- a conta foi excluída;
- o sistema entrou em manutenção.

## Roles

Roles atuais:

```text
ADM
DEV
```

O pacote compartilhado define permissões de interface/compatibilidade para evitar que os dois aplicativos usem regras diferentes.

### ADM

Permissões de contrato atuais:

```text
app1.session.use
app1.admin
```

ADM não recebe permissão privilegiada de DEV.

### DEV

Permissões de contrato atuais:

```text
app1.session.use
app1.admin
app1.dev.privileged
app1.social.pin-post
```

`app1.social.pin-post` apenas reserva no contrato a decisão já aprovada para o futuro Feed Social. Isso **não significa que o Social já foi implementado**.

## Autoridade server-side

As permissões compartilhadas podem ser usadas pelo cliente para decidir quais controles mostrar, mas não substituem verificação no backend.

Exemplo futuro: quando o endpoint de fixar publicação Social existir, o servidor deverá consultar a role atual da conta e aceitar somente `DEV`, mesmo que um cliente ADM tente chamar a API manualmente.

## App 1 Probe

`apps/app1-probe` continua sendo uma sonda de compatibilidade, não o Aplicativo 1 final.

Na V0.6 ela testa:

1. login com ADM/DEV criado pelo Keymaster;
2. recebimento de token de sessão;
3. armazenamento seguro local do token de teste;
4. revalidação em `/v1/app1/me`;
5. leitura de role/status;
6. aplicação do contrato compartilhado de permissões;
7. limpeza da sessão local de teste.

A revogação server-side continua sendo controlada pelo Keymaster/API.
