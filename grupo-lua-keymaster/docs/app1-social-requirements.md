# GRUPO LUA — APP 1 / SOCIAL — REQUISITOS SALVOS

Status: **REQUISITO APROVADO / AINDA NÃO IMPLEMENTADO**

Este documento registra decisões do Aplicativo 1 antes do início do desenvolvimento completo da área Social. A implementação do App 1 continua adiada; o desenvolvimento atual permanece focado no Aplicativo 2 — Keymaster.

## Feed Social — mensagens fixadas por DEV

1. Somente contas com `role = DEV` podem fixar ou desafixar publicações no feed Social.
2. A opção deve aparecer no menu de ações da publicação, por exemplo no botão `⋮`, como:
   - `Fixar mensagem`
   - `Desafixar mensagem`
3. A permissão deve ser validada no servidor. Alterar a interface ou enviar uma requisição manual como ADM não pode conceder o direito de fixar.
4. Uma publicação fixada deve guardar, no mínimo:
   - `isPinned`
   - `pinnedAt`
   - `pinnedBy`
5. Publicações fixadas aparecem acima das publicações normais para todos os usuários do feed.
6. Entre publicações fixadas, a ordenação é por `pinnedAt DESC`: a última publicação que um DEV fixou deve aparecer em primeiro lugar.
7. A publicação fixada mais recente deve receber destaque visual forte no topo do feed, com identidade vermelha, incluindo uma borda/aura vermelha ao redor e indicação clara de que foi fixada por DEV.
8. O destaque visual não substitui a regra server-side de ordenação. O servidor deve retornar o feed já respeitando a prioridade das mensagens fixadas.

### Ordenação prevista

```text
1. isPinned = true, pinnedAt mais recente primeiro
2. demais publicações por createdAt mais recente primeiro
```

## Notificações administrativas

Quando um DEV fixar uma publicação:

1. os outros administradores devem receber uma notificação;
2. a notificação deve informar que um DEV fixou uma mensagem/publicação no feed;
3. deve identificar o DEV responsável quando disponível;
4. ao tocar na notificação, o Aplicativo 1 deve abrir diretamente a publicação correspondente;
5. a notificação deve ser criada pelo backend junto da ação de fixar para manter consistência entre feed e notificações.

Exemplo de texto:

```text
Pablo fixou uma publicação no feed Social.
```

## Segurança / autoridade

- `ADM` comum não pode fixar publicação.
- `DEV` pode fixar/desafixar.
- O backend valida a role atual da conta no momento da ação.
- A ordenação do feed deve ser definida pelo servidor, não apenas pelo cliente.
- A criação das notificações administrativas deve ocorrer no mesmo fluxo server-side da ação de fixar.

## Escopo atual

Este arquivo existe apenas para preservar as decisões antes do desenvolvimento do Aplicativo 1. **Não iniciar a implementação completa de Social, Chats, Arquivos, Feed ou Notificações do App 1 sem uma nova confirmação do usuário.**
