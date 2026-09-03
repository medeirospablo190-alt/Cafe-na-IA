# GRUPO LUA — APP 1 / SOCIAL — REQUISITOS ATUAIS

Status: **APROVADO PARA IMPLEMENTAÇÃO**

A especificação completa está em `docs/app1-v1-master-spec.md`. Este arquivo mantém um resumo específico da área Social.

## Feed mobile-first

Cada post mostra ações na ordem:

```text
Like | Comentários | Favorito
```

- Like: público e com contador;
- Comentários: contador visível, conteúdo fechado por padrão;
- Favorito: público, com contador e lista de perfis que favoritaram.

## Comentários

Ao tocar em Comentários:

- o card do post expande para baixo;
- comentários são carregados consecutivamente;
- existe campo para novo comentário;
- respostas são permitidas;
- visual mobile usa apenas um nível de recuo;
- respostas a respostas podem usar `@Nome` sem aumentar recuo indefinidamente;
- usar paginação/“Ver mais” para evitar cards enormes;
- comentários/respostas podem conter texto, figurinha ou ambos.

## Favoritos

Favoritos de posts são públicos.

No post:

- mostra quantidade;
- tocar no contador abre quem favoritou;
- tocar em um perfil abre o perfil correspondente.

No perfil:

```text
POSTS | FAVORITOS
```

A aba Favoritos mostra os posts marcados por aquele perfil.

Um post com pelo menos um favorito é preservado além da retenção normal de 24 horas. Quando o último favorito é removido e o post já passou da janela normal, ele volta a ser elegível para limpeza.

Conversas favoritas são privadas e seguem regra separada.

## Likes

- um like por conta/post;
- contador público;
- idempotência server-side;
- notificações próprias.

## Pin oficial DEV

A regra atual substitui a versão antiga de múltiplos pins:

1. somente DEV pode fixar/desafixar;
2. existe **um único post principal fixado por vez**;
3. fixar outro substitui automaticamente o anterior;
4. o anterior volta ao feed normal;
5. estado e ordenação são server-side;
6. auditoria registra DEV, post, horário e post substituído;
7. o post permanece preservado enquanto estiver fixado.

## Identidade DEV

- tag DEV só para role DEV real;
- anel/moldura vermelha oficial automática;
- ADM não pode selecionar identidade DEV;
- tag DEV não pode ser ocultada;
- ações/publicações oficiais podem usar acento vermelho sem pintar a interface inteira.

## Notificações Social

A central de Social é separada de mensagens privadas.

Categorias:

```text
TODAS | CURTIDAS | COMENTÁRIOS | FAVORITOS
```

Mensagens ficam em ícone/contador próprio.

Notificações expiram após 24h. A remoção da notificação não apaga conteúdo preservado.

## Retenção

- posts normais: 24h;
- favoritos/pin podem preservar o post;
- comentários/respostas/likes continuam ligados ao post enquanto ele existir;
- notificações: 24h;
- chaves, menus, scripts, arquivos, configurações, perfil, stickers e auditoria não entram na limpeza automática Social.

## Busca de perfis

A busca do Feed pesquisa somente identidade pública/perfis.

Não retorna:

- login;
- credencial;
- posts como resultado de pesquisa de perfil;
- chats;
- chaves;
- arquivos;
- IP/dispositivo.

A busca exige sessão válida e aplica validação, consulta parametrizada, rate limit, paginação e proteção contra enumeração automatizada.

## Pseudônimo

O Social usa `publicName`, nunca o login interno.

No primeiro acesso, o usuário deve escolher um pseudônimo aprovado pelo servidor. A interface avisa para não usar nome real, login, chave ou informações pessoais.

## Mensagem global DEV

DEV terá função de anúncio global:

- permissionada no servidor;
- auditada;
- separada de chat privado e post comum;
- pode gerar notificação geral.

## Privacidade de chats

Enquanto a conta estiver ACTIVE, não existe função administrativa comum para abrir chats privados. Em caso de denúncia que exija investigação, a conta pode ser suspensa e somente então um fluxo autorizado/auditado pode liberar o conteúdo necessário para análise.
